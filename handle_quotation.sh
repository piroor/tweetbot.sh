#!/usr/bin/env bash

tools_dir="$(cd "$(dirname "$0")" && pwd)"
tweet_sh="$tools_dir/tweet.sh/tweet.sh"

base_dir="$TWEET_BASE_DIR"
log_dir="$TWEET_BASE_DIR/logs"
logfile="$log_dir/handle_quotation.log"

source "$tweet_sh"
load_keys

log() {
  echo "$*" 1>&2
  echo "[$(date)] $*" >> "$logfile"
}

while read -r tweet
do
  screen_name="$(echo "$tweet" | jq -r .user.screen_name)"
  id="$(echo "$tweet" | jq -r .id_str)"
  url="https://twitter.com/$screen_name/status/$id"

  log "Quoted by $screen_name at $url"

  log " => follow $screen_name"
  "$tweet_sh" follow $screen_name > /dev/null

  log " => favorite $url"
  "$tweet_sh" favorite $url > /dev/null

  body="$(echo "$tweet" | "$tweet_sh" body)"
  me="$(echo "$tweet" | jq -r .quoted_status.user.screen_name)"
  log " me: $me"
  log " body: $body"
  if echo "$body" | grep "^@$me" > /dev/null
  then
    log "Seems to be a reply."
    response="$(echo "$body" | "$responder" | tr -d '\n')"
    log " response: $response"
    if [ "$response" != '' ]
    then
      "$tweet_sh" reply "$url" "$response"
    fi
  else
    log "Seems to be an RT with quotation."
    log " => retweet $url"
    "$tweet_sh" retweet $url > /dev/null
  fi
done
