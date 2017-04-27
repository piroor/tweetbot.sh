#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
source "$tools_dir/common.sh"
logfile="$log_dir/handle_dm.log"

administrators="$(echo "$ADMINISTRATORS" |
                    $esed -e "s/^[$whitespaces]*,[$whitespaces]*|[$whitespaces]*,[$whitespaces]*$//g" \
                          -e "s/[$whitespaces]*,[$whitespaces]*/|/g")"
if [ "$administrators" = '' ]
then
  exit 1
fi

remove_first_arg() {
  $esed 's/^[^ ]+ +//'
}

respond() {
  local sender="$1"
  shift
  "$tweet_sh" dm "$sender" "$*" > /dev/null
}

run_user_defined_command() {
  local sender="$1"
  local body="$2"
  log 'Running given command...'
  local command="$(echo "$body" | remove_first_arg)"
  find "$TWEET_BASE_DIR" -type f -name 'on_command*' | while read path
  do
    log 'Processing user defined command...'
    log " command line: \"$path\"  \"$sender\" \"$command\""
    cd "$TWEET_BASE_DIR"
    local handler_result
    handler_result="$("$path" "$sender" "$command" 2>&1)"
    if [ $? = 0 ]
    then
      log "$handler_result"
      log "Successfully processed."
      respond "$sender" "Successfully processed: \"$command\" by \"$(basename "$path")\""
    else
      log 'Failed to process.'
      log "$handler_result"
      respond "$sender" "Failed to run \"$command\" by \"$(basename "$path")\""
    fi
  done
}

do_echo() {
  local sender="$1"
  local body="$2"
  log 'Responding an echo...'
  local tweet_body="$(echo "$body" | remove_first_arg)"
  local result
  result="$(respond "$sender" "$tweet_body")"
  if [ $? = 0 ]
  then
    log "Successfully responded: \"$tweet_body\""
  else
    log "$result"
    log "Failed to respond \"$tweet_body\""
  fi
}

test_response() {
  local sender="$1"
  local body="$2"
  log 'Testing to reply...'
  cd $TWEET_BASE_DIR
  local tweet_body="$(echo "$body" | remove_first_arg | "$responder")"
  local result
  result="$(respond "$sender" "$tweet_body")"
  if [ $? = 0 ]
  then
    log "Successfully responded: \"$tweet_body\""
  else
    log "$result"
    log "Failed to respond \"$tweet_body\""
  fi
}

modify_response() {
  local sender="$1"
  local body="$2"
  local output="$(echo "$body" | "$tools_dir/modify_response.sh" 2>&1)"
  local result=$?
  log "$output"
  respond "$sender" "$(echo "$output" | paste -s -d ', ')"
  if [ $result = 0 ]
  then
    find "$TWEET_BASE_DIR" -type f -name 'on_response_modified*' | while read path
    do
      log "Processing \"$path\"..."
      cd $TWEET_BASE_DIR
      local handler_result
      handler_result="$("$path" 2>&1)"
      if [ $? = 0 ]
      then
        log 'Successfully proceeded.'
      else
        log 'Failed to process.'
        log "$handler_result"
      fi
    done
    respond "$sender" "Response patterns are successfully modified for \"$body\""
  else
    respond "$sender" "Failed to modify response patterns for \"$body\""
  fi
}

modify_monologue() {
  local sender="$1"
  local body="$2"
  local output="$(echo "$body" | "$tools_dir/modify_monologue.sh" 2>&1)"
  local result=$?
  log "$output"
  respond "$sender" "$(echo "$output" | paste -s -d ', ')"
  if [ $result = 0 ]
  then
    find "$TWEET_BASE_DIR" -type f -name 'on_monologue_modified*' | while read path
    do
      log "Processing \"$path\"..."
      cd $TWEET_BASE_DIR
      local handler_result
      handler_result="$("$path" 2>&1)"
      if [ $? = 0 ]
      then
        log 'Successfully proceeded.'
      else
        log 'Failed to process.'
        log "$handler_result"
      fi
    done
    respond "$sender" "Monologue patterns are successfully modified for \"$body\""
  else
    respond "$sender" "Failed to modify monologue patterns for \"$body\""
  fi
}

post() {
  local sender="$1"
  local body="$2"
  log 'Posting new tweet...'
  local output
  output="$("$tweet_sh" post "$body" 2>&1)"
  if [ $? = 0 ]
  then
    log "Successfully posted: \"$body\""
    respond "$sender" "Successfully posted: \"$body\""
  else
    log "$output"
    log "Failed to post \"$body\""
    respond "$sender" "Failed to post \"$body\""
  fi
}

reply_to() {
  local sender="$1"
  local body="$2"
  log 'Replying...'
  local reply_params="$(echo "$body" | $esed 's/^reply +//i')"
  local reply_target="$(echo "$reply_params" | $esed 's/^([^ ]+) .*/\1/')"
  local reply_body="$(echo "$reply_params" | $esed 's/^[^ ]+ //')"
  local output
  output="$("$tweet_sh" reply "$reply_target" "$reply_body" 2>&1)"
  if [ $? = 0 ]
  then
    log "Successfully replied to \"$reply_target\": \"$reply_body\""
    respond "$sender" "Successfully replied: \"$reply_body\" to \"$reply_target\""
  else
    log "$output"
    log "Failed to reply to \"$reply_target\": \"$reply_body\""
    respond "$sender" "Failed to reply \"$reply_body\" to \"$reply_target\""
  fi
}

process_generic_command() {
  local sender="$1"
  local body="$2"
  log "Processing $body..."
  local output
  output="$("$tweet_sh" $body 2>&1)"
  if [ $? = 0 ]
  then
    log "Successfully processed: \"$body\""
    respond "$sender" "Successfully processed: \"$body\""
  else
    log "$output"
    log "Failed to process \"$body\""
    respond "$sender" "Failed to process \"$body\""
  fi
}

handle_search_result() {
  local sender="$1"
  local body="$2"
  log 'Processing a search result...'
  local target="$(echo "$body" | remove_first_arg)"
  local tweet="$("$tweet_sh" fetch "$target")"
  
  local output
  output="$(echo "$tweet" | env FORCE_PROCESS=yes "$tools_dir/handle_search_result.sh" 2>&1)"
  if [ $? = 0 ]
  then
    log "Successfully processed a search result: \"$target\""
    respond "$sender" "Successfully processed a search result: \"$target\""
  else
    log "$output"
    log "Failed to process a search result \"$target\""
    respond "$sender" "Failed to process a search result \"$target\""
  fi
}

lock_key=''

while unlock "$lock_key" && read -r message
do
  sender="$(echo "$message" | jq -r .sender_screen_name)"
  id="$(echo "$message" | jq -r .id_str)"

  lock_key="dm.$id"
  try_lock_until_success "$lock_key"

  log '=============================================================='
  log "DM $id from $sender"

  if [ "$sender" = "$MY_SCREEN_NAME" ]
  then
    log " => ignored, because this is my activity"
    continue
  fi

  if echo "$message" | expired_by_seconds $((30 * 60))
  then
    log " => ignored, because this is sent 30 minutes or more ago"
    continue
  fi

  if echo "$sender" | egrep -v "$administrators" > /dev/null
  then
    log ' => not an administrator, ignore it'
    continue
  fi

  if is_already_processed_dm "$id"
  then
    log ' => already processed, ignore it'
    continue
  fi

  body="$(echo "$message" | "$tweet_sh" body)"
  log " body    : $body"

  command_name="$(echo "$body" | $esed "s/^([^ ]+).*$/\1/")"
  log "command name = $command_name"
  case "$command_name" in
    run )
      run_user_defined_command "$sender" "$body"
      ;;
    echo )
      do_echo "$sender" "$body"
      ;;
    test )
      test_response "$sender" "$body"
      ;;
    +res*|-res* )
      modify_response "$sender" "$body"
      ;;
    +*|-* )
      modify_monologue "$sender" "$body"
      ;;
    'tweet!'|'post!' )
      body="$(echo "$body" | remove_first_arg)"
      post "$sender" "$body"
      ;;
    tweet|post )
      body="$(echo "$body" | remove_first_arg)"
      queue="post $body"
      echo "$queue" > "$command_queue_dir/$id.post"
      echo "dm $sender Queued command is processed: \"$queue\"" \
        >> "$command_queue_dir/$id.post"
      log "Command queued: \"$queue\""
      respond "$sender" "Command queued: \"$queue\""
      ;;
    reply )
      reply_to "$sender" "$body"
      ;;
    'rt!'|'retweet!' )
      body="$(echo "$body" | remove_first_arg)"
      process_generic_command "$sender" "retweet $body"
      ;;
    rt|retweet )
      body="$(echo "$body" | remove_first_arg)"
      queue="retweet $body"
      echo "$queue" > "$command_queue_dir/$id.retweet"
      echo "dm $sender Queued command is processed: \"$queue\"" \
        >> "$command_queue_dir/$id.retweet"
      log "Command queued: \"$queue\""
      respond "$sender" "Command queued: \"$queue\""
      ;;
    'favrt!'|'rtfav!'|'fr!'|'rf!' )
      body="$(echo "$body" | remove_first_arg)"
      process_generic_command "$sender" "favorite $body"
      process_generic_command "$sender" "retweet $body"
      ;;
    favrt|rtfav|fr|rf )
      body="$(echo "$body" | remove_first_arg)"
      echo "favorite $body" > "$command_queue_dir/$id.retweet"
      echo "retweet $body" >> "$command_queue_dir/$id.retweet"
      echo "dm $sender Queued command is processed: \"fav and rt $body\"" \
        >> "$command_queue_dir/$id.retweet"
      log "Command queued: \"fav and rt $body\""
      respond "$sender" "Command queued: \"fav and rt $body\""
      ;;
    del*|rem*|unrt|unretweet|fav*|unfav*|follow|unfollow )
      process_generic_command "$sender" "$body"
      ;;
    search-result )
      handle_search_result "$sender" "$body"
      ;;
  esac

  on_dm_processed "$id"
done
