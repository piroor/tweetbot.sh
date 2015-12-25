#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
tweet_sh="$tools_dir/tweet.sh/tweet.sh"
logfile="$work_dir/handle_quotation.log"

source "$tweet_sh"
load_keys

log() {
  echo "$*" 1>&2
  echo "[$(date)] $*" >> "$logfile"
}

me="$("$tweet_sh" whoami)"

while read -r tweet
do
  screen_name="$(echo "$tweet" | jq -r .user.screen_name)"
  log "Quoted by $screen_name"

  log " => follow $screen_name"
  "$tweet_sh" follow $screen_name > /dev/null

  id="$(echo "$tweet" | jq -r .id_str)"
  url="https://twitter.com/$screen_name/status/$id"
  log " => favorite $url"
  "$tweet_sh" favorite $url > /dev/null

  body="$(echo "$tweet" | "$tweet_sh" body)"
  if echo "$body" | grep "^@$me" > /dev/null
  then
    log "Seems to be a reply."
  else
    log "Seems to be an RT with quotation."
    log " => retweet $url"
    "$tweet_sh" retweet $url > /dev/null
  fi
done
