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
  screen_name="$(echo "$event" | jq -r .source.screen_name)"

  log '=============================================================='
  log "Followed by $screen_name"

  log " => follow back $screen_name"
  result="$("$tweet_sh" follow $screen_name)"
  if [ $? != 0 ]
  then
    log "  => failed to follow $screen_name"
    log "     result: $result"
  fi
done
