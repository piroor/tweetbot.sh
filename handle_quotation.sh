#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
source "$tools_dir/common.sh"

logfile="$log_dir/handle_quotation.log"

while read -r tweet
do
  owner="$(echo "$tweet" | jq -r .user.screen_name)"
  id="$(echo "$tweet" | jq -r .id_str)"
  url="https://twitter.com/$owner/status/$id"

  log '=============================================================='
  log "Quoted by $owner at $url"

  if echo "$tweet" | expired_by_seconds $((30 * 60))
  then
    log " => ignored, because this is tweeted 30 minutes or more ago"
    continue
  fi

  if is_already_replied "$id"
  then
    log '  => already responded'
    continue
  fi

  body="$(echo "$tweet" | "$tweet_sh" body)"
  me="$(echo "$tweet" | jq -r .quoted_status.user.screen_name)"
  log " me: $me"
  log " body    : $body"

  is_reply=$(echo "$tweet" | is_reply)
  log " is_reply: $is_reply"

  export SCREEN_NAME="$owner"
  export IS_REPLY=$is_reply
  responses="$(echo "$body" | "$responder")"

  if [ "$responses" = '' ]
  then
    # Don't follow, favorite, and reply to the tweet
    # if it is a "don't respond" case.
    log " no response"
    continue
  fi

  echo "$body" | cache_body "$id"

  is_true "$FOLLOW_ON_QUOTED" && (echo "$tweet" | follow_owner)
  is_true "$FAVORITE_QUOTATIONS" && (echo "$tweet" | favorite)

  if echo "$body" | grep "^@$me" > /dev/null
  then
    log "Seems to be a reply."
    log " response: $response"
    is_true "$RESPOND_TO_QUOTATIONS" && (
      echo "$responses" |
        post_replies "$owner" "$id"
    )
  else
    log "Seems to be an RT with quotation."
    echo "$tweet" | retweet
    is_true "$RETWEET_QUOTATIONS" && (echo "$tweet" | retweet)
  fi
done
