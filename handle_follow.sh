#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
source "$tools_dir/common.sh"
logfile="$log_dir/handle_follow.log"

lock_key=''

while unlock "$lock_key" && read -r event
do
  follower="$(echo "$event" | jq -r .source.screen_name)"

  lock_key="follow.$follower"
  try_lock_until_success "$lock_key"

  log '=============================================================='
  log "Followed by $follower"

  if [ "$follower" = "$MY_SCREEN_NAME" ]
  then
    log " => ignored, because this is my activity"
    continue
  fi

  user="$(echo "$event" | jq -c .source)"

  if echo "$user" | is_protected_user
  then
    log " => protected user should not be followed to avoid privacy issues"
    continue
  fi

  if echo "$user" | is_spam_like_user
  then
    log " => spam like user should not be followed"
    continue
  fi

  if is_true "$FOLLOW_ON_FOLLOWED"
  then
    log " => follow back $follower"
    result="$("$tweet_sh" follow $follower)"
    if [ $? = 0 ]
    then
      log '  => successfully followed'
    else
      log "  => failed to follow $follower"
      log "     result: $result"
    fi
  fi
done
