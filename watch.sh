#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
source "$tools_dir/common.sh"

if [ ! -f "$TWEET_BASE_DIR/tweet.client.key" ]
then
  log "FATAL ERROR: Missing key file at $TWEET_BASE_DIR/tweet.client.key"
  exit 1
fi

"$tools_dir/generate_responder.sh"


# Initialize required informations to call APIs

me="$("$tools_dir/tweet.sh/tweet.sh" showme)"
my_screen_name="$(echo "$me" | jq -r .screen_name | tr -d '\n')"
lang="$(echo "$me" | jq -r .lang | tr -d '\n')"
if [ "$lang" = 'null' -o "$lang" = '' ]
then
  lang="en"
fi

log " my screen name: $my_screen_name"
log " lang          : $lang"

export TWEET_SCREEN_NAME="$my_screen_name"


# Initialize list of search queries

query=''
keywords=''
if [ "$WATCH_KEYWORDS" != '' ]
then
  log "Building search query from \"$WATCH_KEYWORDS\""
  query="$(echo "$WATCH_KEYWORDS" |
    $esed -e "s/^[$whitespaces]*,[$whitespaces]*|[$whitespaces]*,[$whitespaces]*$//g" \
          -e "s/[$whitespaces]*,[$whitespaces]*/ OR /g")"
  keywords="$(echo ",$WATCH_KEYWORDS," |
    # Ignore CJK quieries, because then never appear in the stream.
    $esed -e "s/^[$whitespaces]*,[$whitespaces]*|[$whitespaces]*,[$whitespaces]*$//g" \
          -e 's/,[^,!-~]+,//g' \
          -e "s/[$whitespaces]*,+[$whitespaces]*/,/g" \
          -e 's/^,|,$//g')"
fi


# Kill all forked children always!
# Ctrl-C sometimes fails to kill descendant processes,
# so we have to use custom "kill_descendants" function...

self_pid=$$
trap 'kill_descendants $self_pid; exit 0' HUP INT QUIT KILL TERM


# Sub process 1: watching mentions with the streaming API

COMMON_ENV="env TWEET_SCREEN_NAME=\"$TWEET_SCREEN_NAME\" TWEET_BASE_DIR=\"$TWEET_BASE_DIR\""
"$tools_dir/tweet.sh/tweet.sh" watch-mentions \
  -k "$keywords" \
  -m "$COMMON_ENV $tools_dir/handle_mention.sh" \
  -r "$COMMON_ENV $tools_dir/handle_retweet.sh" \
  -q "$COMMON_ENV $tools_dir/handle_quotation.sh" \
  -f "$COMMON_ENV $tools_dir/handle_follow.sh" \
  -d "$COMMON_ENV $tools_dir/handle_dm.sh" \
  -s "$COMMON_ENV $tools_dir/handle_search_result.sh" \
  &


# Sub process 2: polling for the REST search API
#   This is required, because not-mention CJK tweets with keywords
#   won't appear in the stream tracked by "watch-mentions" command.
#   For more details of this limitation, see also:
#   https://dev.twitter.com/streaming/overview/request-parameters#track

periodical_search() {
  local count=100
  local last_id_file="$status_dir/last_search_result"
  local last_id=''
  [ -f "$last_id_file" ] && last_id="$(cat "$last_id_file")"
  local keywords_for_search_results="$(echo "$query" | sed 's/ OR /,/g')"
  local id
  local type
  if [ "$last_id" != '' ]
  then
    log "Doing search for newer than $last_id"
  fi

  while true
  do
    debug "Processing results of REST search API..."
    while read -r tweet
    do
      debug "=> $tweet"
      [ "$tweet" = '' ] && continue
      id="$(echo "$tweet" | jq -r .id_str)"
      [ "$id" = '' -o "$id" = 'null' ] && continue
      [ "$last_id" = '' ] && last_id="$id"
      if [ $id -gt $last_id ]
      then
        last_id="$id"
        echo "$last_id" > "$last_id_file"
      fi
      type="$(echo "$tweet" |
                "$tools_dir/tweet.sh/tweet.sh" type \
                  -s "$my_screen_name" \
                  -k "$keywords_for_search_results")"
      debug "   type: $type"
      case "$type" in
        mention )
          # When the REST search founds the tweet, it also appears
          # into the streaming API. To prevent duplicated responses,
          # I handle it with delay for now...
          sleep 30s
          echo "$tweet" | "$tools_dir/handle_mention.sh"
          ;;
        retweet )
          echo "$tweet" | "$tools_dir/handle_retweet.sh"
          ;;
        quotation )
          # Same to mentions.
          sleep 30s
          echo "$tweet" | "$tools_dir/handle_quotation.sh"
          ;;
        search-result )
          echo "$tweet" | "$tools_dir/handle_search_result.sh"
          ;;
      esac
      sleep 3s
    done < <("$tools_dir/tweet.sh/tweet.sh" search \
                -q "$query" \
                -l "$lang" \
                -c "$count" \
                -s "$last_id" |
                jq -c '.statuses[]')
    if [ "$last_id" != '' ]
    then
      # increment "since id" to bypass cached search results
      last_id="$(($last_id + 1))"
      echo "$last_id" > "$last_id_file"
    fi
    sleep 2m
  done
}
if [ "$query" != '' ]
then
  log "Tracking search results with the query \"$query\"..."
  periodical_search &
else
  log "No search queriy."
fi

# Sub process 3: polling for the REST direct messages API
#   This is required, because some direct messages can be dropped
#   in the stream.

periodical_fetch_direct_messages() {
  local count=100
  local last_id_file="$status_dir/last_fetched_dm"
  local last_id=''
  [ -f "$last_id_file" ] && last_id="$(cat "$last_id_file")"
  local id
  if [ "$last_id" != '' ]
  then
    log "Fetching for newer than $last_id"
  fi

  while true
  do
    debug "Processing results of REST direct messages API..."
    while read -r message
    do
      debug "=> $message"
      [ "$message" = '' ] && continue
      id="$(echo "$message" | jq -r .id_str)"
      [ "$id" = '' -o "$id" = 'null' ] && continue
      [ "$last_id" = '' ] && last_id="$id"
      if [ $id -gt $last_id ]
      then
        last_id="$id"
        echo "$last_id" > "$last_id_file"
      fi
      echo "$message" | "$tools_dir/handle_dm.sh"
      sleep 3s
    done < <("$tools_dir/tweet.sh/tweet.sh" fetch-direct-messages \
                -c "$count" \
                -s "$last_id" |
                jq -c '.[]')
    [ "$last_id" != '' ] && echo "$last_id" > "$last_id_file"
    sleep 3m
  done
}
periodical_fetch_direct_messages &


wait
