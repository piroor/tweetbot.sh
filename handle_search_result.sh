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

  log '=============================================================='
  log "Search result found, tweeted by $screen_name at $url"

  created_at="$(echo "$tweet" | jq -r .created_at)"
  created_at=$(date -d "$created_at" +%s)
  now=$(date +%s)
  if [ $((now - created_at)) -gt $((24 * 60 * 60)) ]
  then
    log " => ignored, because this is tweeted one day or more ago"
    continue
  fi

  body="$(echo "$tweet" | "$tweet_sh" body)"
  log " body    : $body"

  if echo "$body" | grep "^RT @[^:]+:" > /dev/null
  then
    log " => ignored, because this is a retweet"
    continue
  fi

  response="$(echo "$body" | "$responder")"
  if [ $? != 0 -o "$response" = '' ]
  then
    # Don't favorite and reply to the tweet
    # if it is a "don't respond" case.
    log " => don't response case"
    continue
  fi

  # log " => follow $screen_name"
  # "$tweet_sh" follow $screen_name > /dev/null

  if echo "$tweet" | jq -r .favorited | grep "false"
  then
    log " => favorite $url"
    result="$("$tweet_sh" favorite $url)"
    if [ $? != 0 ]
    then
      log '  => failed to favorite'
      log "     result: $result"
    fi
  else
    log " => already favorited"
  fi

  if echo "$tweet" | jq -r .retweeted | grep "false"
  then
    log " => retweet $url"
    result="$("$tweet_sh" retweet $url)"
    if [ $? != 0 ]
    then
      log '  => failed to retweet'
      log "     result: $result"
    fi
  else
    log " => already retweeted"
  fi
done
