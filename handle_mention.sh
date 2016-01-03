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

  key="mention.$id"
  try_lock_until_success "$key"

  log '=============================================================='
  log "Mentioned by $owner at $url"

  if echo "$tweet" | expired_by_seconds $((30 * 60))
  then
    log " => ignored, because this is tweeted 30 minutes or more ago"
    unlock "$key"
    continue
  fi

  if is_already_replied "$id"
  then
    log '  => already replied'
    unlock "$key"
    continue
  fi

  body="$(echo "$tweet" | "$tweet_sh" body)"
  log " body    : $body"

  is_reply=$(echo "$tweet" | is_reply && echo 1)
  log " is_reply: $is_reply"

  export SCREEN_NAME="$owner"
  export IS_REPLY=$is_reply
  responses="$(echo "$body" | "$responder")"

  if [ "$responses" = '' ]
  then
    # Don't follow, favorite, and reply to the tweet
    # if it is a "don't respond" case.
    log " no response"
    unlock "$key"
    continue
  fi

  echo "$body" | cache_body "$id"

  log ' responses:'
  log "$responses"

  if is_true "$FOLLOW_ON_MENTIONED"
  then
    echo "$tweet" | follow_owner
  fi
  if is_true "$FAVORITE_MENTIONS"
  then
    echo "$tweet" | favorite
  fi
  if is_true "$RETWEET_MENTIONS"
  then
    echo "$tweet" | retweet
  fi

  if is_true "$RESPOND_TO_MENTIONS"
  then
    echo "$responses" |
      # make response body a mention
      sed "s/^/@${owner} /" |
      post_replies "$id"
  fi

  unlock "$key"
done
