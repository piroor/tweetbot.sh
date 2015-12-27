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

while read -r tweet
do
  screen_name="$(echo "$tweet" | jq -r .user.screen_name)"
  id="$(echo "$tweet" | jq -r .id_str)"
  url="https://twitter.com/$screen_name/status/$id"

  log '=============================================================='
  log "Search result found, tweeted by $screen_name at $url"

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
    log '  => failed to favorite'
    log "     result: $result"
  fi
  else
    log " => already retweeted"
  fi
done
