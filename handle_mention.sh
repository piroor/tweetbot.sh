#!/usr/bin/env bash

tools_dir="$(cd "$(dirname "$0")" && pwd)"
tweet_sh="$tools_dir/tweet.sh/tweet.sh"

base_dir="$TWEET_BASE_DIR"
log_dir="$TWEET_BASE_DIR/logs"
logfile="$log_dir/handle_search_result.log"

source "$tweet_sh"
load_keys

log() {
  echo "$*" 1>&2
  echo "[$(date)] $*" >> "$logfile"
}

responder="$TWEET_BASE_DIR/responder.sh"

while read -r tweet
do
  screen_name="$(echo "$tweet" | jq -r .user.screen_name)"
  id="$(echo "$tweet" | jq -r .id_str)"
  url="https://twitter.com/$screen_name/status/$id"

  log "Mentioned by $screen_name at $url"

  log " => follow $screen_name"
  "$tweet_sh" follow $screen_name > /dev/null

  log " => favorite $url"
  "$tweet_sh" favorite $url > /dev/null

  body="$(echo "$tweet" | "$tweet_sh" body)"
  log " body    : $body"

  response="$(echo "$body" | "$responder" | tr -d '\n')"
  log " response: $response"
  if [ "$response" != '' ]
  then
    "$tweet_sh" reply "$url" "@$screen_name $response"
  fi
done
