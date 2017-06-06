#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
source "$tools_dir/common.sh"

logfile="$log_dir/handle_mention.log"

lock_key=''

while unlock "$lock_key" && read -r tweet
do
  owner="$(echo "$tweet" | jq -r .user.screen_name)"
  id="$(echo "$tweet" | jq -r .id_str)"
  url="https://twitter.com/$owner/status/$id"

  lock_key="mention.$id"
  try_lock_until_success "$lock_key"

  log '=============================================================='
  log "Mentioned by $owner at $url"

  if [ "$owner" = "$MY_SCREEN_NAME" ]
  then
    log " => ignored, because this is my activity"
    continue
  fi

  if echo "$tweet" | expired_by_seconds $((30 * 60))
  then
    log " => ignored, because this is tweeted 30 minutes or more ago"
    continue
  fi

  if is_already_replied "$id"
  then
    log '  => already replied'
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
    other_replied_people="$(echo "$body" | other_replied_people)"

    if is_false "$RESPOND_TO_MULTIPLE_TARGETS_MENTIONS"
    then
      log " response for a mention with other people is not allowed"
      continue
    fi

    echo "$responses" |
      # make response body a mention
      sed "s/^/@$owner $other_replied_people/" |
      post_replies "$id" "@$owner $other_replied_people"
  fi
done
