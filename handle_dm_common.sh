#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
source "$tools_dir/common.sh"
logfile="$log_dir/handle_dm.log"

administrators="$(echo "$ADMINISTRATORS" |
                    sed -E -e "s/^[$whitespaces]*,[$whitespaces]*|[$whitespaces]*,[$whitespaces]*$//g" \
                          -e "s/[$whitespaces]*,[$whitespaces]*/|/g")"
if [ "$administrators" = '' ]
then
  exit 1
fi

remove_first_arg() {
  sed -E 's/^[^ ]+ +//'
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
  local reply_params="$(echo "$body" | sed -E 's/^reply +//i')"
  local reply_target="$(echo "$reply_params" | sed -E 's/^([^ ]+) .*/\1/')"
  local reply_body="$(echo "$reply_params" | sed -E 's/^[^ ]+ //')"
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

delete_queued_command_for() {
  local target="$1"
  grep -r "$target" "$command_queue_dir" | cut -d ':' -f 1 | uniq | xargs rm -f
}

