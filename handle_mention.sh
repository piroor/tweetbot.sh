#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
source "$tools_dir/common.sh"

logfile="$log_dir/handle_mention.log"

while read -r tweet
do
  owner="$(echo "$tweet" | jq -r .user.screen_name)"
  id="$(echo "$tweet" | jq -r .id_str)"
  url="https://twitter.com/$owner/status/$id"

  log '=============================================================='
  log "Mentioned by $owner at $url"

  if echo "$tweet" | expired_by_seconds $((30 * 60))
  then
    log " => ignored, because this is tweeted 30 minutes or more ago"
    continue
  fi

  body="$(echo "$tweet" | "$tweet_sh" body)"
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

  log ' responses:'
  log "$responses"

  is_true "$FOLLOW_ON_MENTIONED" && (echo "$tweet" | follow_owner)
  is_true "$FAVORITE_MENTIONS" && (echo "$tweet" | favorite)
  is_true "$RETWEET_MENTIONS" && (echo "$tweet" | retweet)

  if is_already_replied "$id"
  then
    log '  => already replied'
    continue
  fi

  is_true "$RESPOND_TO_MENTIONS" && (
    echo "$responses" |
    sed "s/^/@${owner} /" |
    post_replies "$id"
  )
done
