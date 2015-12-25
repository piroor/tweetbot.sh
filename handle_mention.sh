#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
tweet_sh="$tools_dir/tweet.sh/tweet.sh"
logfile="$work_dir/handle_mention.log"

log() {
  echo "[$(date)] $*" >> "$logfile"
}

source "$tweet_sh"
load_keys

echo "MENTIONED"
while read tweet
do
  echo "$tweet"
done
