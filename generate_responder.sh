#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
tweet_sh="$tools_dir/tweet.sh/tweet.sh"

source "$tweet_sh"

if [ "$TWEET_BASE_DIR" != '' ]
then
  TWEET_BASE_DIR="$(cd "$TWEET_BASE_DIR" && pwd)"
else
  TWEET_BASE_DIR="$work_dir"
fi

responder="$TWEET_BASE_DIR/responder.sh"

ls "$TWEET_BASE_DIR/responses/*" |
  sort |
  while read path
do
  echo "$path"
done
