#!/usr/bin/env bash

tools_dir="$(cd "$(dirname "$0")" && pwd)"
tweet_sh="$tools_dir/tweet.sh/tweet.sh"

base_dir="$TWEET_BASE_DIR"
log_dir="$TWEET_BASE_DIR/logs"
logfile="$log_dir/handle_dm.log"

source "$tweet_sh"
load_keys

log() {
  echo "$*" 1>&2
  echo "[$(date)] $*" >> "$logfile"
}

responder="$TWEET_BASE_DIR/responder.sh"

administrators="$(cat "$TWEET_BASE_DIR/administrators.txt" |
                    sed 's/^\s+|\s+$//' |
                    paste -s -d '|')"
if [ "$administrators" = '' ]
then
  exit 1
fi

run_command() {
  local body="$1"
  log 'Running given command...'
  local command="$(echo "$body" | $esed 's/^[^ ]+ +//i')"
  find "$TWEET_BASE_DIR" -type f -name 'on_command*' | while read path
  do
    log "Processing \"$path\"..."
    local handler_result="$("$path" "$command" 2>&1)"
    if [ $? = 0 ]
    then
      log "$result"
      log "Successfully processed."
      "$tweet_sh" dm $sender "Successfully processed: \"$command\" by \"$(basename "$path")\"" > /dev/null
    else
      log 'Failed to process.'
      log "$handler_result"
      "$tweet_sh" dm $sender "Failed to run \"$command\" by \"$(basename "$path")\"" > /dev/null
    fi
  done
}

do_echo() {
  local body="$1"
  log 'Responding an echo...'
  local tweet_body="$(echo "$body" | $esed 's/^[^ ]+ +//i')"
  local result="$("$tweet_sh" dm $sender "$tweet_body" > /dev/null)"
  if [ $? = 0 ]
  then
    log "Successfully responded: \"$tweet_body\""
  else
    log "$result"
    log "Failed to respond \"$tweet_body\""
  fi
}

test_response() {
  local body="$1"
  log 'Testing to reply...'
  local tweet_body="$(echo "$body" | $esed 's/^[^ ]+ +//i' | "$responder")"
  local result="$("$tweet_sh" dm $sender "$tweet_body" > /dev/null)"
  if [ $? = 0 ]
  then
    log "Successfully responded: \"$tweet_body\""
  else
    log "$result"
    log "Failed to respond \"$tweet_body\""
  fi
}

modify_response() {
  local body="$1"
  local output="$(echo "$body" | "$tools_dir/modify_response.sh" 2>&1)"
  local result=$?
  log "$output"
  if [ $result = 0 ]
  then
    find "$TWEET_BASE_DIR" -type f -name 'on_response_modified*' | while read path
    do
      log "Processing \"$path\"..."
      local handler_result="$("$path" 2>&1)"
      if [ $? = 0 ]
      then
        log 'Successfully proceeded.'
      else
        log 'Failed to process.'
        log "$handler_result"
      fi
    done
    "$tweet_sh" dm $sender "Response patterns are successfully modified for \"$body\"" > /dev/null
  else
    "$tweet_sh" dm $sender "Failed to modify response patterns for \"$body\"" > /dev/null
  fi
}

post() {
  local body="$1"
  log 'Posting new tweet...'
  local tweet_body="$(echo "$body" | $esed 's/^(tweet|post) +//i')"
  local output="$("$tweet_sh" post "$tweet_body" 2>&1)"
  if [ $? = 0 ]
  then
    log "Successfully posted: \"$tweet_body\""
    "$tweet_sh" dm $sender "Successfully posted: \"$tweet_body\"" > /dev/null
  else
    log "$output"
    log "Failed to post \"$tweet_body\""
    "$tweet_sh" dm $sender "Failed to post \"$tweet_body\"" > /dev/null
  fi
}

reply() {
  local body="$1"
  log 'Replying...'
  local reply_params="$(echo "$body" | $esed 's/^reply +//i')"
  local reply_target="$(echo "$reply_params" | $esed 's/^([^ ]+) .*/\1/')"
  local reply_body="$(echo "$reply_params" | $esed 's/^[^ ]+ //')"
  local output="$("$tweet_sh" reply "$reply_target" "$reply_body" 2>&1)"
  if [ $? = 0 ]
  then
    log "Successfully replied to \"$reply_target\": \"$reply_body\""
    "$tweet_sh" dm $sender "Successfully replied: \"$reply_body\" to \"$reply_target\"" > /dev/null
  else
    log "$output"
    log "Failed to reply to \"$reply_target\": \"$reply_body\""
    "$tweet_sh" dm $sender "Failed to reply \"$reply_body\" to \"$reply_target\"" > /dev/null
  fi
}

delete() {
  local body="$1"
  log 'Deleting...'
  local delete_target="$(echo "$body" | $esed 's/^[^ ]+ +//i')"
  local output="$("$tweet_sh" delete "$delete_target" 2>&1)"
  if [ $? = 0 ]
  then
    log "Successfully deleted: \"$delete_target\""
    "$tweet_sh" dm $sender "Successfully deleted: \"$delete_target\"" > /dev/null
  else
    log "$output"
    log "Failed to delete \"$delete_target\""
    "$tweet_sh" dm $sender "Failed to delete \"$delete_target\"" > /dev/null
  fi
}

retweet() {
  log 'Retweeting...'
  local retweet_target="$(echo "$body" | $esed 's/^[^ ]+ +//i')"
  local output="$("$tweet_sh" retweet "$retweet_target" 2>&1)"
  result=$?
  if [ $result = 0 ]
  then
    log "Successfully retweeted: \"$retweet_target\""
    "$tweet_sh" dm $sender "Successfully retweeted: \"$retweet_target\"" > /dev/null
  else
    log "$output"
    log "Failed to retweet \"$retweet_target\""
    "$tweet_sh" dm $sender "Failed to retweet \"$retweet_target\"" > /dev/null
  fi
}

while read -r message
do
  sender="$(echo "$message" | "$tweet_sh" owner)"

  log '=============================================================='
  log "DM from $sender"

  body="$(echo "$message" | "$tweet_sh" body)"
  log " body    : $body"

  if echo "$sender" | egrep -v "$administrators" > /dev/null
  then
    log ' => not an administrator, ignore it'
    continue
  fi

  command_name="$(echo "$body" | $esed "s/^([ ]+).*$/\1/")"
  case "$command_name" in
    run )
      run_command "$body"
      ;;
    echo )
      do_echo "$body"
      ;;
    test )
      test_response "$body"
      ;;
    +res*|-res* )
      modify_response "$body"
      ;;
    tweet|post )
      post "$body"
      ;;
    reply )
      reply "$body"
      ;;
    del*|rem* )
      delete "$body"
      ;;
    rt|retweet )
      retweet "$body"
      ;;
  esac
done
