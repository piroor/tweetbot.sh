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
  owner="$(echo "$tweet" | jq -r .user.screen_name)"
  id="$(echo "$tweet" | jq -r .id_str)"
  url="https://twitter.com/$owner/status/$id"

  log '=============================================================='
  log "Mentioned by $owner at $url"

  body="$(echo "$tweet" | "$tweet_sh" body)"
  log " body    : $body"

  response="$(echo "$body" | "$responder")"
  if [ $? != 0 -o "$response" = '' ]
  then
    # Don't follow, favorite, and reply to the tweet
    # if it is a "don't respond" case.
    log " no response"
    continue
  fi
  log " response: $response"

  log " => follow $owner"
  result="$("$tweet_sh" follow $owner)"
  if [ $? = 0 ]
  then
    log '  => successfully followed'
  else
    log "  => failed to follow $owner"
    log "     result: $result"
  fi

  log " => favorite $url"
  result="$("$tweet_sh" favorite $url)"
  if [ $? = 0 ]
  then
    log '  => successfully favorited'
  else
    log '  => failed to favorite'
    log "     result: $result"
  fi

  result="$("$tweet_sh" reply "$url" "@$owner $response")"
  if [ $? = 0 ]
  then
    log '  => successfully respond'
  else
    log '  => failed to reply'
    log "     result: $result"
  fi
done
