#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
source "$tools_dir/common.sh"
logfile="$log_dir/handle_follow.log"

while read -r event
do
  follower="$(echo "$event" | jq -r .source.screen_name)"

  log '=============================================================='
  log "Followed by $follower"

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
