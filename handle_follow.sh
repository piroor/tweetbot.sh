#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
tweet_sh="$tools_dir/tweet.sh/tweet.sh"
logfile="$work_dir/handle_follow.log"

source "$tweet_sh"
load_keys

log() {
  echo "$*" 1>&2
  echo "[$(date)] $*" >> "$logfile"
}

while read event
do
  screen_name="$(echo "$event" | jq -r .source.screen_name)"
  log "Followed by $screen_name"
  log " => follow back $screen_name"
  "$tweet_sh" follow $screen_name > /dev/null
done
