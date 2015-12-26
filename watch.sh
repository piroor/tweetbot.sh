#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
tweet_sh="$tools_dir/tweet.sh/tweet.sh"

source "$tweet_sh"
load_keys

if [ "$TWEET_BASE_DIR" != '' ]
then
  TWEET_BASE_DIR="$(cd "$TWEET_BASE_DIR" && pwd)"
else
  TWEET_BASE_DIR="$work_dir"
fi

logs_dir="$TWEET_BASE_DIR/logs"
mkdir -p "$logs_dir"


"$tools_dir/generate_responder.sh"


queries_file="$TWEET_BASE_DIR/queries.txt"
queries=''
if [ -f "$queries_file" ]
then
  echo "Reading search queries from \"$queries_file\"" 1>&2
  queries="$(grep -v '^\s*#' "$queries_file" | \
               grep -v '^\s*$' | \
               paste -s -d ",")"
fi

"$tools_dir/tweet.sh/tweet.sh" watch-mentions \
  -k "$queries" \
  -m "env TWEET_BASE_DIR=\"$TWEET_BASE_DIR\" $tools_dir/handle_mention.sh" \
#  -r "env TWEET_BASE_DIR=\"$TWEET_BASE_DIR\" $tools_dir/handle_retweet.sh" \
  -q "env TWEET_BASE_DIR=\"$TWEET_BASE_DIR\" $tools_dir/handle_quotation.sh" \
  -f "env TWEET_BASE_DIR=\"$TWEET_BASE_DIR\" $tools_dir/handle_follow.sh" \
  -s "env TWEET_BASE_DIR=\"$TWEET_BASE_DIR\" $tools_dir/handle_search_result.sh"