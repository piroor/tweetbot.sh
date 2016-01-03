#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
source "$tools_dir/common.sh"

logfile="$log_dir/handle_retweet.log"

lock_key=''

while unlock "$lock_key" && read -r tweet
do
  owner="$(echo "$tweet" | jq -r .user.screen_name)"
  id="$(echo "$tweet" | jq -r .id_str)"
  url="https://twitter.com/$owner/status/$id"

  lock_key="retweet.$id"
  try_lock_until_success "$lock_key"

  log '=============================================================='
  log "Retweeted by $owner at $url"

  if is_true "$FOLLOW_ON_RETWEETED"
  then
    echo "$tweet" | follow_owner
  fi
done
