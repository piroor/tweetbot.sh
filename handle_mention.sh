#!/usr/bin/env bash

tools_dir="$(cd "$(dirname "$0")" && pwd)"
tweet_sh="$tools_dir/tweet.sh/tweet.sh"

base_dir="$TWEET_BASE_DIR"
log_dir="$TWEET_BASE_DIR/logs"
logfile="$log_dir/handle_mention.log"

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
  result="$("$tweet_sh" follow $screen_name)"
  if [ $? != 0 ]
  then
    log "  => failed to follow $screen_name"
    log "     result: $result"
  fi

  log " => favorite $url"
  result="$("$tweet_sh" favorite $url)"
  if [ $? != 0 ]
  then
    log '  => failed to favorite'
    log "     result: $result"
  fi

  body="$(echo "$tweet" | "$tweet_sh" body)"
  log " body    : $body"

  response="$(echo "$body" | "$responder" | tr -d '\n')"
  log " response: $response"
  if [ "$response" != '' ]
  then
    result="$("$tweet_sh" reply "$url" "@$screen_name $response")"
    if [ $? != 0 ]
    then
      log '  => failed to reply'
      log "     result: $result"
    fi
  fi
done
