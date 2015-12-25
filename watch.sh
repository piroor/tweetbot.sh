#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"

source "$tools_dir/tweet.sh/tweet.sh"
load_keys

trap 'jobs="$(jobs -p)"; [ "$jobs" = "" ] || kill $jobs' QUIT KILL TERM


queries_file="$work_dir/queries.txt"
if [ -f "$queries_file" ]
then
  echo "Reading search queries from \"$queries_file\"" 1>&2
  queries="$(grep -v '^\s*#' "$queries_file" | \
               grep -v '^\s*$' | \
               paste -s -d " OR ")
  if [ "$queries" != '' ]
  then
    "$tools_dir/tweet.sh/tweet.sh" search \
      -q "$queries" \
      -h "$tools_dir/handle_search_result.sh"
    exit 0
  fi
fi

echo "There is no search query at \"$queries_file\"" 1>&2

"$tools_dir/tweet.sh/tweet.sh" watch-mentions \
  -m "$tools_dir/handle_mention.sh" \
  -r "$tools_dir/handle_retweet.sh" \
  -q "$tools_dir/handle_quotation.sh" \
  -f "$tools_dir/handle_follow.sh"