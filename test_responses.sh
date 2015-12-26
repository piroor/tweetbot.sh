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

me="$("$tweet_sh" whoami)"

cd "$TWEET_BASE_DIR"

ls ./responses/* |
  sort |
  while read path
do
  # first, convert CR+LF => LF
  nkf -Lu "$path" |
    # ignore comment and blank lines
    egrep -v '^#|^\s*$' |
    while read -r response
    do
      "$tweet_sh" post "@$me $response"
    done
  sleep 3s
done