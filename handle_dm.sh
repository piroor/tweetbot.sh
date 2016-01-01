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

respond() {
  local sender="$1"
  shift
  "$tweet_sh" dm "$sender" "$*" > /dev/null
}

run_command() {
  local sender="$1"
  local body="$2"
  log 'Running given command...'
  local command="$(echo "$body" | $esed 's/^[^ ]+ +//i')"
  find "$TWEET_BASE_DIR" -type f -name 'on_command*' | while read path
  do
    log "Processing \"$path\"..."
    cd $TWEET_BASE_DIR
    local handler_result="$("$path" "$sender" "$command" 2>&1)"
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
  local tweet_body="$(echo "$body" | $esed 's/^[^ ]+ +//i')"
  local result="$(respond "$sender" "$tweet_body")"
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
  local tweet_body="$(echo "$body" | $esed 's/^[^ ]+ +//i' | "$responder")"
  local result="$(respond "$sender" "$tweet_body")"
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
  if [ $result = 0 ]
  then
    find "$TWEET_BASE_DIR" -type f -name 'on_response_modified*' | while read path
    do
      log "Processing \"$path\"..."
      cd $TWEET_BASE_DIR
      local handler_result="$("$path" 2>&1)"
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

modify_scheduled_message() {
  local sender="$1"
  local body="$2"
  local output="$(echo "$body" | "$tools_dir/modify_scheduled_message.sh" 2>&1)"
  local result=$?
  log "$output"
  if [ $result = 0 ]
  then
    find "$TWEET_BASE_DIR" -type f -name 'on_scheduled_message_modified*' | while read path
    do
      log "Processing \"$path\"..."
      cd $TWEET_BASE_DIR
      local handler_result="$("$path" 2>&1)"
      if [ $? = 0 ]
      then
        log 'Successfully proceeded.'
      else
        log 'Failed to process.'
        log "$handler_result"
      fi
    done
    respond "$sender" "Scheduled message patterns are successfully modified for \"$body\""
  else
    respond "$sender" "Failed to modify scheduled message patterns for \"$body\""
  fi
}

post() {
  local sender="$1"
  local body="$2"
  log 'Posting new tweet...'
  local tweet_body="$(echo "$body" | $esed 's/^(tweet|post) +//i')"
  local output="$("$tweet_sh" post "$tweet_body" 2>&1)"
  if [ $? = 0 ]
  then
    log "Successfully posted: \"$tweet_body\""
    respond "$sender" "Successfully posted: \"$tweet_body\""
  else
    log "$output"
    log "Failed to post \"$tweet_body\""
    respond "$sender" "Failed to post \"$tweet_body\""
  fi
}

reply() {
  local sender="$1"
  local body="$2"
  log 'Replying...'
  local reply_params="$(echo "$body" | $esed 's/^reply +//i')"
  local reply_target="$(echo "$reply_params" | $esed 's/^([^ ]+) .*/\1/')"
  local reply_body="$(echo "$reply_params" | $esed 's/^[^ ]+ //')"
  local output="$("$tweet_sh" reply "$reply_target" "$reply_body" 2>&1)"
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

delete() {
  local sender="$1"
  local body="$2"
  log 'Deleting...'
  local delete_target="$(echo "$body" | $esed 's/^[^ ]+ +//i')"
  local output="$("$tweet_sh" delete "$delete_target" 2>&1)"
  if [ $? = 0 ]
  then
    log "Successfully deleted: \"$delete_target\""
    respond "$sender" "Successfully deleted: \"$delete_target\""
  else
    log "$output"
    log "Failed to delete \"$delete_target\""
    respond "$sender" "Failed to delete \"$delete_target\""
  fi
}

retweet() {
  local sender="$1"
  local body="$2"
  log 'Retweeting...'
  local retweet_target="$(echo "$body" | $esed 's/^[^ ]+ +//i')"
  local output="$("$tweet_sh" retweet "$retweet_target" 2>&1)"
  result=$?
  if [ $result = 0 ]
  then
    log "Successfully retweeted: \"$retweet_target\""
    respond "$sender" "Successfully retweeted: \"$retweet_target\""
  else
    log "$output"
    log "Failed to retweet \"$retweet_target\""
    respond "$sender" "Failed to retweet \"$retweet_target\""
  fi
}

while read -r message
do
  sender="$(echo "$message" | jq -r .sender_screen_name)"
  id="$(echo "$message" | jq -r .id_str)"

  log '=============================================================='
  log "DM $id from $sender"

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

  if [ -f "$already_processed_dir/$id" ]
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
      run_command "$sender" "$body"
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
      modify_scheduled_message "$sender" "$body"
      ;;
    tweet|post )
      post "$sender" "$body"
      ;;
    reply )
      reply "$sender" "$body"
      ;;
    del*|rem* )
      delete "$sender" "$body"
      ;;
    rt|retweet )
      retweet "$sender" "$body"
      ;;
  esac

  touch "$already_processed_dir/$id"
  # remove too old files - store only for recent N messages
  ls "$already_processed_dir/" | sort | head -n -200 | while read path
  do
    rm -rf "$path"
  done
done
