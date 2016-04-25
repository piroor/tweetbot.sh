#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
source "$tools_dir/common.sh"
logfile="$log_dir/handle_search_result.log"

lock_key=''

queue_dir="$status_dir/search_result_queue"
mkdir -p "$queue_dir"

while unlock "$lock_key" && read -r tweet
do
  screen_name="$(echo "$tweet" | jq -r .user.screen_name)"
  id="$(echo "$tweet" | jq -r .id_str)"
  url="https://twitter.com/$screen_name/status/$id"

  lock_key="search_result.$id"
  try_lock_until_success "$lock_key"

  log '=============================================================='
  log "Search result found, tweeted by $screen_name at $url"

  if [ "$owner" = "$MY_SCREEN_NAME" ]
  then
    log " => ignored, because this is my activity"
    continue
  fi

  if [ "$FORCE_PROCESS" != 'yes' ]
    then
    if echo "$tweet" | expired_by_seconds $((24 * 60 * 60))
    then
      log " => ignored, because this is tweeted one day or more ago"
      continue
    fi
  fi

  body="$(echo "$tweet" | "$tweet_sh" body)"
  log " body    : $body"

  if echo "$body" | egrep "^RT @[^:]+:" > /dev/null
  then
    log " => ignored, because this is a retweet"
    continue
  fi

  export SCREEN_NAME="$owner"
  responses="$(echo "$body" | "$responder")"
  if [ $? != 0 -o "$responses" = '' ]
  then
    # Don't favorite and reply to the tweet
    # if it is a "don't respond" case.
    log " => don't response case"
    continue
  fi

  echo "$tweet" > "$queue_dir/queued.$id.$screen_name"
done
