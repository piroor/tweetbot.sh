#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
tweet_sh="$tools_dir/tweet.sh/tweet.sh"

if [ "$TWEET_BASE_DIR" != '' ]
then
  TWEET_BASE_DIR="$(cd "$TWEET_BASE_DIR" && pwd)"
else
  TWEET_BASE_DIR="$work_dir"
fi

base_dir="$TWEET_BASE_DIR"
log_dir="$TWEET_BASE_DIR/logs"
logfile="$log_dir/general.log"

source "$tweet_sh"
load_keys

log() {
  echo "$*" 1>&2
  echo "[$(date)] $*" >> "$logfile"
}

responder="$TWEET_BASE_DIR/responder.sh"
already_replied_dir="$TWEET_BASE_DIR/already_replied"


# default personality

FOLLOW_ON_FOLLOWED=true
FOLLOW_ON_MENTIONED=true
FOLLOW_ON_QUOTED=true
FOLLOW_ON_RETWEETED=true

FAVORITE_MENTIONS=true
FAVORITE_QUOTATIONS=true
FAVORITE_SEARCH_RESULTS=true

RETWEET_MENTIONS=false
RETWEET_QUOTATIONS=true
RETWEET_SEARCH_RESULTS=true

RESPOND_TO_MENTIONS=true
RESPOND_TO_QUOTATIONS=true

personality_file="$TWEET_BASE_DIR/personality.txt"
if [ -f "$personality_file" ]
then
  source "$personality_file"
fi

is_true() {
  egrep -i "^(1|true|yes)$"
}

expired_by_seconds() {
  local expire_seconds=$1
  local tweet="$(cat)"
  local created_at="$(echo "$tweet" | jq -r .created_at)"
  local created_at=$(date -d "$created_at" +%s)
  local now=$(date +%s)
  [ $((now - created_at)) -gt $expire_seconds ]
}

is_reply() {
  local replied_id="$(jq -r .in_reply_to_status_id_str)"
  if [ "$replied_id" != 'null' -a "$replied_id" != '' ]
  then
    echo 1
  else
    echo 0
  fi
}

follow_owner() {
  local tweet="$(cat)"
  local id="$(echo "$tweet" | jq -r .id_str)"
  local owner="$(echo "$tweet" | jq -r .user.screen_name)"

  log "Trying to follow to the owner of $id, $owner..."

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
}

favorite() {
  local tweet="$(cat)"
  local id="$(echo "$tweet" | jq -r .id_str)"

  log "Trying to favorite $id..."

  if echo "$tweet" | jq -r .favorited | grep "false"
  then
    log " => favorite $id"
    result="$("$tweet_sh" favorite $id)"
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
}

retweet() {
  local tweet="$(cat)"
  local id="$(echo "$tweet" | jq -r .id_str)"

  log "Trying to retweet $id..."

  if echo "$tweet" | jq -r .retweeted | grep "false"
  then
    log " => retweet $id"
    result="$("$tweet_sh" retweet $id)"
    if [ $? != 0 ]
    then
      log '  => failed to retweet'
      log "     result: $result"
    fi
  else
    log " => already retweeted"
  fi
}

is_already_replied() {
  local id=$1
  [ -f "$already_replied_dir/$id" ]
}

post_replies() {
  local id=$1

  log "Sending replies to $id..."
  while read -r body
  do
    local result="$("$tweet_sh" reply "$id" "$body")"
    if [ $? = 0 ]
    then
      log '  => successfully responded'
      touch "$already_replied_dir/$id"
      # remove too old files
      find "$already_replied_dir" -ctime +1 | while read path
      do
        rm -rf "$path"
      done
      # send following resposnes as a sequential tweets
      id="$(echo "$result" | jq -r .id_str)"
    else
      log '  => failed to reply'
      log "     result: $result"
    fi
  done
}
