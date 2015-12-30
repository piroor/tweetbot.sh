#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
tweet_sh="$tools_dir/tweet.sh/tweet.sh"

source "$tweet_sh"
load_keys

if [ "$TWEET_BASE_DIR" != '' ]
then
  TWEET_BASE_DIR="$(cd "$TWEET_BASE_DIR" && pwd)"
else
  TWEET_BASE_DIR="$work_dir"
fi
export TWEET_BASE_DIR

base_dir="$TWEET_BASE_DIR"

log_dir="$TWEET_BASE_DIR/logs"
mkdir -p "$log_dir"

logfile="$log_dir/general.log"

log() {
  echo "$*" 1>&2
  echo "[$(date)] $*" >> "$logfile"
}

debug() {
  [ "$DEBUG" = '' ] && return 0
  echo "$*" 1>&2
  echo "[$(date)] debug: $*" >> "$logfile"
}

responder="$TWEET_BASE_DIR/responder.sh"

status_dir="$TWEET_BASE_DIR/.status"
mkdir -p "$status_dir"

already_replied_dir="$status_dir/already_replied"
mkdir -p "$already_replied_dir"

already_processed_dir="$status_dir/already_processed"
mkdir -p "$already_processed_dir"

body_cache_dir="$status_dir/body_cache"
mkdir -p "$body_cache_dir"

responses_dir="$TWEET_BASE_DIR/responses"
mkdir -p "$responses_dir"


whitespaces=' \f\n\r\t@'
non_whitespaces='[^ \f\n\r\t@]'


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
RESPOND_TO_SEARCH_RESULTS=true

OBSESSION_TO_SELF_TOPICS=75
FREQUENCY_OF_CAPRICES=66
ENDLESSNESS=66
CONVERSATION_SPAN=40

MAX_BODY_CACHE=1000
ADMINISTRATORS=''
WATCH_KEYWORDS=''

personality_file="$TWEET_BASE_DIR/personality.txt"
if [ -f "$personality_file" ]
then
  source "$personality_file"
fi

is_true() {
  echo "$1" | egrep -i "^(1|true|yes)$" > /dev/null
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

on_replied() {
  local id="$1"
  touch "$already_replied_dir/$id"
  # remove too old files
  find "$already_replied_dir" -ctime +1 | while read path
  do
    rm -rf "$path"
  done
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
      on_replied "$id"
      # send following resposnes as a sequential tweets
      id="$(echo "$result" | jq -r .id_str)"
      echo "$body" | cache_body "$id"
    else
      log '  => failed to reply'
      log "     result: $result"
    fi
  done
}

post_quotation() {
  local owner=$1
  local id=$2
  local url="https://twitter.com/$owner/status/$id"

  log "Quoting the tweet $id by $owner..."
  while read -r body
  do
    local result="$("$tweet_sh" reply "$id" "$body $url")"
    if [ $? = 0 ]
    then
      log '  => successfully quoted'
      on_replied "$id"
      # send following resposnes as a sequential tweets
      id="$(echo "$result" | jq -r .id_str)"
      echo "$body $url" | cache_body "$id"
    else
      log '  => failed to quote'
      log "     result: $result"
    fi
  done
}

cache_body() {
  local id="$1"
  cat > "$body_cache_dir/$id"

  # remove too old caches - store only for recent N bodies
  ls "$body_cache_dir/" | sort | head -n -$MAX_BODY_CACHE | while read path
  do
    rm -rf "$path"
  done
}

