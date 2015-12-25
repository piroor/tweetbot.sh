#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
tweet_sh="$tools_dir/tweet.sh/tweet.sh"
logfile="$work_dir/handle_follow.log"

source "$tweet_sh"
load_keys

while read event
do
  screen_name="$(echo "$event" | jq -r .source.screen_name)"
  echo "Followed by $screen_name" >> "$logfile"
  echo " => follow back $screen_name" >> "$logfile"
  "$tweet_sh" follow $screen_name > /dev/null
done
