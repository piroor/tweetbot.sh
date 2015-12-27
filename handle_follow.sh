#!/usr/bin/env bash

tools_dir="$(cd "$(dirname "$0")" && pwd)"
tweet_sh="$tools_dir/tweet.sh/tweet.sh"

base_dir="$TWEET_BASE_DIR"
log_dir="$TWEET_BASE_DIR/logs"
logfile="$log_dir/handle_follow.log"

source "$tweet_sh"
load_keys

log() {
  echo "$*" 1>&2
  echo "[$(date)] $*" >> "$logfile"
}

while read -r event
do
  follower="$(echo "$event" | jq -r .source.screen_name)"

  log '=============================================================='
  log "Followed by $follower"

  log " => follow back $follower"
  result="$("$tweet_sh" follow $follower)"
  if [ $? = 0 ]
  then
    log '  => successfully followed'
  else
    log "  => failed to follow $follower"
    log "     result: $result"
  fi
done
