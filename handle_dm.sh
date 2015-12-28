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

administrators="$(cat "$TWEET_BASE_DIR/administrators.txt" |
                    sed 's/^\s+|\s+$//' |
                    paste -s -d '|')"
if [ "$administrators" = '' ]
then
  exit 1
fi

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

  if echo "$body" | egrep -i '^[+-]res(ponse)?\s' > /dev/null
  then
    output="$(echo "$body" | "$tools_dir/modify_response.sh" 2>&1)"
    result=$?
    log "$output"
    if [ $result = 0 ]
    then
      find "$TWEET_BASE_DIR" -type f -name 'on_response_modified*' | while read path
      do
        log "Processing \"$path\"..."
        handler_result="$("$path" 2>&1)"
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
    continue
  fi

  if echo "$body" | egrep -i "^(tweet|post) " > /dev/null
  then
    log 'Posting new tweet...'
    tweet_body="$(echo "$body" | $esed 's/^(tweet|post) +//i')"
    output="$("$tweet_sh" post "$tweet_body" 2>&1)"
    result=$?
    if [ $result = 0 ]
    then
      log "Successfully posted: \"$tweet_body\""
      "$tweet_sh" dm $sender "Successfully posted: \"$tweet_body\"" > /dev/null
    else
      log "$output"
      log "Failed to post \"$tweet_body\""
      "$tweet_sh" dm $sender "Failed to post \"$tweet_body\"" > /dev/null
    fi
    continue
  fi

  if echo "$body" | egrep -i "^reply " > /dev/null
  then
    log 'Replying...'
    reply_params="$(echo "$body" | $esed 's/^reply +//i')"
    reply_target="$(echo "$reply_params" | $esed 's/^([^ ]+) .*/\1/')"
    reply_body="$(echo "$reply_params" | $esed 's/^[^ ]+ //')"
    output="$("$tweet_sh" reply "$reply_target" "$reply_body" 2>&1)"
    result=$?
    if [ $result = 0 ]
    then
      log "Successfully replied to \"$reply_target\": \"$reply_body\""
      "$tweet_sh" dm $sender "Successfully replied: \"$reply_body\" to \"$reply_target\"" > /dev/null
    else
      log "$output"
      log "Failed to reply to \"$reply_target\": \"$reply_body\""
      "$tweet_sh" dm $sender "Failed to reply \"$reply_body\" to \"$reply_target\"" > /dev/null
    fi
    continue
  fi

  if echo "$body" | egrep -i "^(del(ete)?|rem(ove)?) " > /dev/null
  then
    log 'Deleting...'
    delete_target="$(echo "$body" | $esed 's/^[^ ]+ +//i')"
    output="$("$tweet_sh" delete "$delete_target" 2>&1)"
    result=$?
    if [ $result = 0 ]
    then
      log "Successfully deleted: \"$delete_target\""
      "$tweet_sh" dm $sender "Successfully deleted: \"$delete_target\"" > /dev/null
    else
      log "$output"
      log "Failed to delete \"$delete_target\""
      "$tweet_sh" dm $sender "Failed to delete \"$delete_target\"" > /dev/null
    fi
    continue
  fi
done
