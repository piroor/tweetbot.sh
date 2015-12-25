#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"

source "$tools_dir/tweet.sh"
load_keys

"$tools_dir/tweet.sh/tweet.sh" watch-mentions \
  -m "$tools_dir/handle_mention.sh" \
  -r "$tools_dir/handle_retweet.sh" \
  -q "$tools_dir/handle_quotation.sh" \
  -f "$tools_dir/handle_follow.sh"
