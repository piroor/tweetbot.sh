#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
source "$tools_dir/common.sh"

if [ ! -f "$TWEET_BASE_DIR/tweet.client.key" ]
then
  echo "FATAL ERROR: Missing key file at $TWEET_BASE_DIR/tweet.client.key" 1>&2
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

echo " my screen name: $my_screen_name" 1>&2
echo " lang          : $lang" 1>&2

export TWEET_SCREEN_NAME="$my_screen_name"


# Initialize list of search queries

queries_file="$TWEET_BASE_DIR/queries.txt"
queries=''
keywords=''
if [ -f "$queries_file" ]
then
  echo "Reading search queries from \"$queries_file\"" 1>&2
  queries="$( \
    # First, convert CR+LF => LF for safety.
    nkf -Lu "$queries_file" |
    egrep -v '^\s*$' |
    sed 's/$/ OR /' |
    tr -d '\n' |
    sed 's/ OR $//')"
  keywords="$( \
    # First, convert CR+LF => LF for safety.
    nkf -Lu "$queries_file" |
    # Ignore CJK quieries, because then never appear in the stream.
    egrep -i '^[!-~]+$' |
    egrep -v '^\s*$' |
    paste -s -d ',')"
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
  echo " queries: $queries" 1>&2

  local count=100
  local last_id_file="$status_dir/last_search_result"
  local last_id=''
  [ -f "$last_id_file" ] && last_id="$(cat "$last_id_file")"
  local keywords_for_search_results="$(echo "$queries" | sed 's/ OR /,/g')"
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
                -q "$queries" \
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
[ "$queries" != '' ] && periodical_search &


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
