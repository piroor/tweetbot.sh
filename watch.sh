#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"

source "$tools_dir/tweet.sh/tweet.sh"
load_keys

trap 'jobs="$(jobs -p)"; [ "$jobs" = "" ] || kill $jobs' QUIT KILL TERM


queries_file="$work_dir/queries.txt"
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
  -m "$tools_dir/handle_mention.sh" \
  -r "$tools_dir/handle_retweet.sh" \
  -q "$tools_dir/handle_quotation.sh" \
  -f "$tools_dir/handle_follow.sh" \
  -s "$tools_dir/handle_search_result.sh"