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
"$tools_dir/generate_monologue_selector.sh"


# Initialize required informations to call APIs

log " my screen name: $MY_SCREEN_NAME"
log " lang          : $MY_LANGUAGE"
if [ "$MY_USER_ID" = '' ]
then
  export MY_USER_ID="$(get_user_id "$MY_SCREEN_NAME")"
  client_key_path="$(detect_client_key_file)"
  echo "MY_USER_ID=$MY_USER_ID" >> "$client_key_path"
fi
log " user id       : $MY_USER_ID"

export TWEET_SCREEN_NAME="$MY_SCREEN_NAME"
export TWEET_USER_ID="$MY_SCREEN_NAME"

if [ "$WATCH_KEYWORDS" != '' ]
then
  log "Search queries from \"$WATCH_KEYWORDS\":"
  log "  query for REST searc : $query"
  log "  keywords for tracking: $keywords"
  log "  search result matcher: $keywords_matcher"
fi

# Kill all forked children always!
# Ctrl-C sometimes fails to kill descendant processes,
# so we have to use custom "kill_descendants" function...
kill_descendants() {
  local target_pid=$1
  local children=$(ps --no-heading --ppid $target_pid -o pid)
  for child in $children
  do
    kill_descendants $child
  done
  if [ $target_pid != $$ ]
  then
    kill $target_pid 2>&1 > /dev/null
  fi
}
self_pid=$$
trap 'kill_descendants $self_pid; clear_all_lock; exit 0' HUP INT QUIT KILL TERM


# Sub process 1: watching mentions with the streaming API

watch_mentions() {
  local COMMON_ENV="env TWEET_SCREEN_NAME=\"$TWEET_SCREEN_NAME\" TWEET_BASE_DIR=\"$TWEET_BASE_DIR\" TWEET_LOGMODULE='streaming'"
  while true
  do
    "$tools_dir/tweet.sh/tweet.sh" watch-mentions \
      -k "$keywords" \
      -m "$COMMON_ENV $tools_dir/handle_mention.sh" \
      -r "$COMMON_ENV $tools_dir/handle_retweet.sh" \
      -q "$COMMON_ENV $tools_dir/handle_quotation.sh" \
      -f "$COMMON_ENV $tools_dir/handle_follow.sh" \
      -d "$COMMON_ENV $tools_dir/handle_dm.sh" \
      -s "$COMMON_ENV $tools_dir/handle_search_result.sh"
    log "Tracking of mentions is unexpectedly stopped. Reconnect after 10sec."
    sleep 10 # for safety
  done
}
#watch_mentions &


# Sub process 2: polling for the REST search API to find QTs

recent_my_tweet_urls() {
  "$tools_dir/tweet.sh/tweet.sh" fetch-tweets -u "$MY_SCREEN_NAME" -a -c 10 |
    jq -r .[].id_str |
    sed -e "s;^;https://twitter.com/$MY_SCREEN_NAME/status/;"
}

extract_new_tweets() {
  local last_id="$1"
  local last_id_file="$2"
  local id
  local owner
  while read -r tweet
  do
    [ "$tweet" = '' ] && continue
    id="$(echo "$tweet" | jq -r .id_str)"
    owner="$(echo "$tweet" | jq -r .user.screen_name)"
    debug "New tweet detected: https://twitter.com/$owner/status/$id"
    [ "$id" = '' -o "$id" = 'null' ] && continue
    [ "$last_id" = '' ] && last_id="$id"
    [ $id -gt $last_id ] && last_id="$id"
    echo "$last_id" > "$last_id_file"
    echo "$tweet"
  done
}

next_last_id() {
  local last_id="$1"
  local last_id_file="$2"
  [ -f "$last_id_file" ] && last_id="$(cat "$last_id_file")"
  if [ "$last_id" != '' ]
  then
    # increment "since id" to bypass cached search results
    last_id="$(($last_id + 1))"
    echo "$last_id" > "$last_id_file"
  fi
  echo -n "$last_id"
}

periodical_search_quotation() {
  logmodule='search_quotation'
  export TWEET_LOGMODULE="$logmodule"
  local count=100
  local last_id_file="$status_dir/last_search_quotation_result"
  local last_id=''
  [ -f "$last_id_file" ] && last_id="$(cat "$last_id_file")"
  local id
  local type
  if [ "$last_id" != '' ]
  then
    log "Doing search for quotations newer than $last_id"
  fi

  while true
  do
    debug "Processing results of REST search API for quotations (newer than $last_id)..."
    "$tools_dir/tweet.sh/tweet.sh" search \
      -q "$(recent_my_tweet_urls | paste -s -d ',' | sed 's/,/ OR /g') -from:$MY_SCREEN_NAME" \
      -c "$count" \
      -s "$last_id" |
      jq -c '.statuses[]' |
      tac |
      extract_new_tweets "$last_id" "$last_id_file" |
      while read -r tweet
      do
        id="$(echo "$tweet" | jq -r .id_str)"
        type="$(echo "$tweet" |
                  "$tools_dir/tweet.sh/tweet.sh" type)"
        debug "   type: $type"
        [ "$type" != 'quotation' ] && continue
        log "Processing $id as $type..."
        echo "$tweet" |
          "$tools_dir/handle_quotation.sh"
        sleep 3s
      done

    last_id="$(next_last_id "$last_id" "$last_id_file")"
    sleep 5m
  done
}

if [ "$FAVORITE_QUOTATIONS" = 'true' -o "$RETWEET_QUOTATIONS" = 'true' -o "$RESPOND_TO_QUOTATIONS" = 'true' ]
then
  log "Tracking search results for quotations..."
  periodical_search_quotation &
fi


# Sub process 3: polling for the REST search API
#   This is required, because not-mention CJK tweets with keywords
#   won't appear in the stream tracked by "watch-mentions" command.
#   For more details of this limitation, see also:
#   https://dev.twitter.com/streaming/overview/request-parameters#track

periodical_search() {
  logmodule='search'
  export TWEET_LOGMODULE="$logmodule"
  local count=100
  local last_id_file="$status_dir/last_search_result"
  local last_id=''
  [ -f "$last_id_file" ] && last_id="$(cat "$last_id_file")"
  local keywords_for_search_results="$(echo "$query" | sed -E -e 's/ OR /,/g' -e 's/-from:[^ ]+//')"
  local id
  local type
  if [ "$last_id" != '' ]
  then
    log "Doing search for newer than $last_id"
  fi

  while true
  do
    debug "Processing results of REST search API (newer than $last_id)..."
    "$tools_dir/tweet.sh/tweet.sh" search \
      -q "$query" \
      -c "$count" \
      -s "$last_id" |
      jq -c '.statuses[]' |
      tac |
      extract_new_tweets "$last_id" "$last_id_file" |
      while read -r tweet
      do
        id="$(echo "$tweet" | jq -r .id_str)"
        type="$(echo "$tweet" |
                  "$tools_dir/tweet.sh/tweet.sh" type \
                    -k "$keywords_for_search_results")"
        debug "   type: $type"
        [ "$type" != '' ] && log "Processing $id as $type..."
        case "$type" in
          mention )
            echo "$tweet" |
              "$tools_dir/handle_mention.sh"
            ;;
          retweet )
            echo "$tweet" |
              "$tools_dir/handle_retweet.sh"
            ;;
          quotation )
            echo "$tweet" |
              "$tools_dir/handle_quotation.sh"
            ;;
          search-result )
            echo "$tweet" |
              "$tools_dir/handle_search_result.sh"
            ;;
        esac
        sleep 3s
      done

    last_id="$(next_last_id "$last_id" "$last_id_file")"
    sleep 3m
  done
}

if [ "$query" != '' ]
then
  log "Tracking search results with the query \"$query\"..."
  periodical_search &
else
  log "No search queriy."
fi


# Sub process 4: polling for the REST direct messages API
#   This is required, because some direct messages can be dropped
#   in the stream.

periodical_fetch_direct_messages() {
  logmodule='dm'
  export TWEET_LOGMODULE="$logmodule"
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
    debug "Processing results of REST direct messages API (newer than $last_id)..."
    while read -r message
    do
      [ "$message" = '' ] && continue
      id="$(echo "$message" | jq -r .id)"
      sender_id="$(echo "$message" | jq -r .message_create.sender_id)"
      [ "$id" = '' -o "$id" = 'null' ] && continue
      [ "$last_id" = '' ] && last_id="$id"
      [ $id -le $last_id ] && continue
      debug "New DM detected: $id"
      last_id="$id"
      echo "$last_id" > "$last_id_file"
      [ "$sender_id" = "$MY_USER_ID" ] && continue
      echo "$message" |
        "$tools_dir/handle_dm_events.sh"
      sleep 3s
    done < <("$tools_dir/tweet.sh/tweet.sh" fetch-direct-messages \
                -c "$count" \
                -s "$last_id" |
                jq -c '.events[]' |
                tac)
    #NOTE: This must be done with a process substitution instead of
    #      simple pipeline, because we need to execute the loop in
    #      the same process, not a sub process.
    #      (sub-process loop produced by "tweet.sh | tac | while read..."
    #       cannot update the "last_id" in this scope.)

    [ -f "$last_id_file" ] && last_id="$(cat "$last_id_file")"
    [ "$last_id" != '' ] && echo "$last_id" > "$last_id_file"
    sleep 2m
  done
}
periodical_fetch_direct_messages &


# Sub process 5: posting monologue tweets

periodical_monologue() {
  logmodule='monologue'
  local last_post_file="$status_dir/last_monologue"
  local last_post_time=''
  [ -f "$last_post_file" ] && last_post_time=$(cat "$last_post_file")

  # minimum interval = 10minutes
  [ $MONOLOGUE_INTERVAL_MINUTES -le 10 ] && MONOLOGUE_INTERVAL_MINUTES=10

  while read last_post_time
  do
    local body="$("$monologue_selector")"
    log "Posting monologue tweet: $body"
    echo "$body" | sed -E -e 's/\t/\n/gi' | post_sequential_tweets
    echo "$last_post_time" > "$last_post_file"
  done < <(run_periodically "$MONOLOGUE_INTERVAL_MINUTES" "$last_post_time" "$MONOLOGUE_ACTIVE_TIME_RANGE")
}
periodical_monologue &


# Sub process 6: polling for the REST search API to follow new users

periodical_auto_follow() {
  logmodule='auto_follow'
  export TWEET_LOGMODULE="$logmodule"
  local count=100
  local last_id_file="$status_dir/last_auto_follow"
  local last_id=''
  [ -f "$last_id_file" ] && last_id="$(cat "$last_id_file")"
  if [ "$last_id" != '' ]
  then
    log "Doing search to auto-follow for newer than $last_id"
  fi

  while true
  do
    debug "Processing results to auto-follow of REST search API (newer than $last_id)..."
    "$tools_dir/tweet.sh/tweet.sh" search \
      -q "$AUTO_FOLLOW_QUERY" \
      -c "$count" \
      -s "$last_id" |
      jq -c '.statuses[]' |
      tac |
      extract_new_tweets "$last_id" "$last_id_file" |
      while read -r tweet
      do
        echo "$tweet" |
          "$tools_dir/handle_follow_target.sh"
        sleep 3s
      done

    last_id="$(next_last_id "$last_id" "$last_id_file")"
    sleep 3m
  done
}
if [ "$AUTO_FOLLOW_QUERY" != '' ]
then
  log "Start to follow search results with the query \"$AUTO_FOLLOW_QUERY\"..."
  periodical_auto_follow &
else
  log "No auto follow queriy."
fi


# Sub process 7: process queued search results and commands

periodical_process_queue() {
  logmodule='process_queue'
  export TWEET_LOGMODULE="$logmodule"
  local last_process_file="$status_dir/queue_last_processed_time"
  local last_process_time=''
  [ -f "$last_process_file" ] && last_process_time=$(cat "$last_process_file")

  # minimum interval = 10minutes
  [ $PROCESS_QUEUE_INTERVALL_MINUTES -le 10 ] && PROCESS_QUEUE_INTERVALL_MINUTES=10

  local next_process_type='search_result'
  while read last_process_time
  do
    debug "Processing queue... (next = $next_process_type)"

    if [ "$next_process_type" = 'search_result' ]
    then
      debug '  trying to process quened search result...'
      env TWEET_LOGMODULE='queued_search_result' "$tools_dir/process_queued_search_result.sh"
      if [ $? = 0 ]
      then
        debug '  => success!'
        next_process_type='command'
        echo "$last_process_time" > "$last_process_file"
        continue
      fi
    fi
    next_process_type='command'

    if [ "$next_process_type" = 'command' ]
    then
      debug '  trying to process quened command...'
      env TWEET_LOGMODULE='queued_command' "$tools_dir/process_queued_command.sh"
      if [ $? = 0 ]
      then
        debug '  => success!'
        next_process_type='search_result'
        echo "$last_process_time" > "$last_process_file"
        continue
      fi
    fi
    next_process_type='search_result'

    echo "$last_process_time" > "$last_process_file"
  done < <(run_periodically "$PROCESS_QUEUE_INTERVALL_MINUTES" "$last_process_time" "$ACTIVE_TIME_RANGE")
  #NOTE: This must be done with a process substitution instead of
  #      simple pipeline, because we need to execute the loop in
  #      the same process to update the "next_process_type",
  #      not a sub process.
}
periodical_process_queue &


wait
