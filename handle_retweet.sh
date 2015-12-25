#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
tweet_sh="$tools_dir/tweet.sh/tweet.sh"
logfile="$work_dir/handle_retweet.log"

log() {
  echo "$*" 1>&2
  echo "[$(date)] $*" >> "$logfile"
}

source "$tweet_sh"
load_keys

echo "RETWEETED"
while read tweet
do
  echo "$tweet"
done
