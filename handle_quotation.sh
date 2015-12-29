#!/usr/bin/env bash

tools_dir="$(cd "$(dirname "$0")" && pwd)"
tweet_sh="$tools_dir/tweet.sh/tweet.sh"

base_dir="$TWEET_BASE_DIR"
log_dir="$TWEET_BASE_DIR/logs"
logfile="$log_dir/handle_quotation.log"

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
  log "Quoted by $owner at $url"

  created_at="$(echo "$tweet" | jq -r .created_at)"
  created_at=$(date -d "$created_at" +%s)
  now=$(date +%s)
  if [ $((now - created_at)) -gt $((30 * 60)) ]
  then
    log " => ignored, because this is tweeted 30 minutes or more ago"
    continue
  fi

  body="$(echo "$tweet" | "$tweet_sh" body)"
  me="$(echo "$tweet" | jq -r .quoted_status.user.screen_name)"
  log " me: $me"
  log " body    : $body"

  replied_id="$(echo "$tweet" | jq -r .in_reply_to_status_id_str)"
  if [ "$replied_id" != 'null' -a "$replied_id" != '' ]
  then
    is_reply=1
  else
    is_reply=0
  fi
  log " is_reply: $is_reply"

  export SCREEN_NAME="$owner"
  export IS_REPLY=$is_reply

  response="$(echo "$body" | "$responder")"
  if [ $? != 0 -o "$response" != '' ]
  then
    # Don't follow, favorite, and reply to the tweet
    # if it is a "don't respond" case.
    log " no response"
    continue
  fi

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

  if echo "$body" | grep "^@$me" > /dev/null
  then
    log "Seems to be a reply."
    log " response: $response"
    if [ -f "$already_replied_dir/$id" ]
    then
      log '  => already responded'
      continue
    fi
    result="$("$tweet_sh" reply "$url" "$response")"
    if [ $? = 0 ]
    then
      log '  => successfully respond'
      touch "$already_replied_dir/$id"
      # remove too old files
      find "$already_replied_dir" -ctime +1 | while read path
      do
        rm -rf "$path"
      done
    else
      log '  => failed to reply'
      log "     result: $result"
    fi
  else
    log "Seems to be an RT with quotation."
    if echo "$tweet" | jq -r .retweeted | grep "false"
    then
      log " => retweet $url"
      result="$("$tweet_sh" retweet $url)"
      if [ $? = 0 ]
      then
        log '  => successfully retweeted'
      else
        log '  => failed to retweet'
        log "     result: $result"
      fi
    else
      log " => already retweeted"
    fi
  fi
done
