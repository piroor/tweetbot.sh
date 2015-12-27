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
already_replied_dir="$TWEET_BASE_DIR/already_replied"

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

  if echo "$tweet" | jq -r .user.following | grep "false"
  then
    log " => follow $owner"
    result="$("$tweet_sh" follow $owner)"
    if [ $? = 0 ]
    then
      log '  => successfully followed'
    else
      log "  => failed to follow $owner"
      log "     result: $result"
    fi
  else
    log " => already followed"
  fi

  if echo "$tweet" | jq -r .favorited | grep "false"
  then
    log " => favorite $url"
    result="$("$tweet_sh" favorite $url)"
    if [ $? = 0 ]
    then
      log '  => successfully favorited'
    else
      log '  => failed to favorite'
      log "     result: $result"
    fi
  else
    log " => already favorited"
  fi

  if [ -f "$already_replied_dir/$id" ]
  then
    log '  => already replied'
    continue
  fi

  result="$("$tweet_sh" reply "$url" "@$owner $response")"
  if [ $? = 0 ]
  then
    log '  => successfully responded'
    touch "$already_replied_dir/$id"
  else
    log '  => failed to reply'
    log "     result: $result"
  fi
done
