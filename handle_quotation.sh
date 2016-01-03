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

  key="quotation.$id"
  try_lock_until_success "$key"

  log '=============================================================='
  log "Quoted by $owner at $url"

  if echo "$tweet" | expired_by_seconds $((30 * 60))
  then
    log " => ignored, because this is tweeted 30 minutes or more ago"
    unlock "$key"
    continue
  fi

  if is_already_replied "$id"
  then
    log '  => already responded'
    unlock "$key"
    continue
  fi

  body="$(echo "$tweet" | "$tweet_sh" body)"
  me="$(echo "$tweet" | jq -r .quoted_status.user.screen_name)"
  log " me: $me"
  log " body    : $body"

  is_reply=$(echo "$tweet" | is_reply && echo 1)
  log " is_reply: $is_reply"

  export SCREEN_NAME="$owner"
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

  if is_true "$FOLLOW_ON_QUOTED"
  then
    echo "$tweet" | follow_owner
  fi
  if is_true "$FAVORITE_QUOTATIONS"
  then
    echo "$tweet" | favorite
  fi
  if is_true "$RETWEET_QUOTATIONS"
  then
    echo "$tweet" | retweet
  fi

  if is_true "$RESPOND_TO_QUOTATIONS"
  then
    if echo "$body" | grep "^@$me" > /dev/null
    then
      log "Seems to be a reply."
      # regenerate responses with is_reply parameter
      responses="$(echo "$body" | env IS_REPLY=$is_reply "$responder")"
      log " response: $response"
      echo "$responses" |
        post_replies "$id"
    elif echo "$body" | egrep "^[\._,:;]?@$me" > /dev/null
    then
      log "Seems to be a mention but for public."
      log " response: $response"
      echo "$responses" |
        post_replies "$id"
    else
      log "Seems to be an RT with quotation."
      # Don't post default questions as quotation!
      responses="$(echo "$body" | env NO_QUESTION=1 "$responder")"
      if [ $? != 0 -o "$responses" = '' ]
      then
        log " => don't quote case"
      else
        echo "$responses" |
          post_quotation "$owner" "$id"
      fi
    fi
  fi

  unlock "$key"
done
