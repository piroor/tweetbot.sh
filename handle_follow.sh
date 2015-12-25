#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
tweet_sh="$tools_dir/tweet.sh/tweet.sh"

source "$tweet_sh"
load_keys

echo "FOLLOWED" 1>&2
while read event
do
  echo "$event"
  screen_name="$(echo "$event" | jq -r .source.screen_name)"
  echo "by $screen_name" 1>&2
  echo "follow back $screen_name" 1>&2
  "$tweet_sh" follow $screen_name
done
