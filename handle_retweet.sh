#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
source "$tools_dir/common.sh"

logfile="$log_dir/handle_retweet.log"

while read -r tweet
do
  owner="$(echo "$tweet" | jq -r .user.screen_name)"
  log '=============================================================='
  log "Retweeted by $owner"
  log "$tweet"
done
