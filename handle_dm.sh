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

  if echo "$body" | egrep -i '^(add|rem(ove)?|del(ete)?)\s' > /dev/null
  then
    output="$(echo "$body" | "$tools_dir/modify_response.sh" 2>&1)"
    result=$?
    log "$output"
    if [ $result = 0 ]
    then
      if [ -f "$TWEET_BASE_DIR/on_response_modified.sh" ]
      then
        "$TWEET_BASE_DIR/on_response_modified.sh"
      fi
      "$tweet_sh" dm $sender "Response patterns are successfully modified for \"$body\""
    else
      "$tweet_sh" dm $sender "Failed to modify response patterns for \"$body\""
    fi
  fi
done
