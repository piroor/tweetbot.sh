#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
source "$tools_dir/common.sh"
logfile="$log_dir/handle_search_result.log"

while read -r tweet
do
  screen_name="$(echo "$tweet" | jq -r .user.screen_name)"
  id="$(echo "$tweet" | jq -r .id_str)"
  url="https://twitter.com/$screen_name/status/$id"

  log '=============================================================='
  log "Search result found, tweeted by $screen_name at $url"

  if echo "$tweet" | is_older_than_N_seconds_before $((24 * 60 * 60))
  then
    log " => ignored, because this is tweeted one day or more ago"
    continue
  fi

  body="$(echo "$tweet" | "$tweet_sh" body)"
  log " body    : $body"

  if [ "$TWEET_SCREEN_NAME" != '' ]
  then
    if echo "$body" | egrep "^@$TWEET_SCREEN_NAME" > /dev/null
    then
      log " => ignored, because this is a mention for me"
      continue
    fi
  fi

  if echo "$body" | egrep "^RT @[^:]+:" > /dev/null
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

  echo "$tweet" | favorite
  echo "$tweet" | retweet
done
