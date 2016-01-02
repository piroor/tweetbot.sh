#!/usr/bin/env bash

#=============================================================
# Initialization

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
tweet_sh="$tools_dir/tweet.sh/tweet.sh"

load_keys() {
  if [ "$CONSUMER_KEY" = '' -a \
       -f "$work_dir/tweet.client.key" ]
  then
    echo 'Using client key at the current directory.' 1>&2
    source "$work_dir/tweet.client.key"
  fi

  if [ "$CONSUMER_KEY" = '' -a \
       -f ~/.tweet.client.key ]
  then
    echo 'Using client key at the home directory.' 1>&2
    source ~/.tweet.client.key
  fi

  if [ "$CONSUMER_KEY" = '' -a \
       -f "$tools_dir/tweet.client.key" ]
  then
    echo 'Using client key at the tools directory.' 1>&2
    source "$tools_dir/tweet.client.key"
  fi

  export CONSUMER_KEY
  export CONSUMER_SECRET
  export ACCESS_TOKEN
  export ACCESS_TOKEN_SECRET
}
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
  [ "$TWEETBOT_DEBUG" = '' ] && return 0
  echo "$*" 1>&2
  echo "[$(date)] debug: $*" >> "$logfile"
}

# Orphan processes can be left after Ctrl-C or something,
# because there can be detached. We manually find them and kill all.
kill_descendants() {
  local target_pid=$1
  local children=$(ps --no-heading --ppid $target_pid -o pid)
  for child in $children
  do
    kill_descendants $child
  done
  if [ $target_pid != $$ ]
  then
    kill $target_pid 2>&1 > /dev/null
  fi
}

responder="$TWEET_BASE_DIR/responder.sh"
autonomic_post_selector="$TWEET_BASE_DIR/autonomic_post_selector.sh"

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

scheduled_messages_dir="$TWEET_BASE_DIR/scheduled"
mkdir -p "$scheduled_messages_dir"


# default personality

FOLLOW_ON_FOLLOWED=true
FOLLOW_ON_MENTIONED=true
FOLLOW_ON_QUOTED=true
FOLLOW_ON_RETWEETED=false

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
NEW_TOPIC=66
CONVERSATION_PERSISTENCE=40

MAX_BODY_CACHE=1000
ADMINISTRATORS=''
WATCH_KEYWORDS=''
INTERVAL_MINUTES=30
AUTONOMIC_POST_TIME_SPAN="morning/06:00-07:00 \
                          noon/12:00-13:00 \
                          afternoon/15:00-15:30 \
                          evening/17:30-18:30 \
                          night/19:00-21:00 \
                          midnight/23:00-24:00,00:00-03:00"

personality_file="$TWEET_BASE_DIR/personality.txt"
if [ -f "$personality_file" ]
then
  source "$personality_file"
fi


#=============================================================
# Utilities to operate primitive strings

whitespaces=' \f\n\r\t@'
non_whitespaces='[^ \f\n\r\t@]'

# Custom version of sed with extended regexp, "$esed" (like "egerp")
case $(uname) in
  Darwin|*BSD|CYGWIN*)
    esed="sed -E"
    ;;
  *)
    esed="sed -r"
    ;;
esac

is_true() {
  echo "$1" | egrep -i "^(1|true|yes)$" > /dev/null
}

time_to_minutes() {
  local now="$1"
  local hours=$(echo "$now" | $esed 's/^0?([0-9]+):.*$/\1/')
  local minutes=$(echo "$now" | $esed 's/^[^:]*:0?([0-9]+)$/\1/')
  echo $(( $hours * 60 + $minutes ))
}

#=============================================================
# Utilities to operate tweet JSON strings

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
  [ "$replied_id" != 'null' -a "$replied_id" != '' ]
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
  local id="$1"
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

# for DM
is_already_processed_dm() {
  local id="$1"
  [ -f "$already_processed_dir/$id" ]
}

on_dm_processed() {
  local id="$1"
  touch "$already_processed_dir/$id"
  # remove too old files - store only for recent N messages
  ls "$already_processed_dir/" | sort | head -n -200 | while read path
  do
    rm -rf "$path"
  done
}


#=============================================================
# Utilities for randomization

choose_random_one() {
  local input="$(cat)"
  local n_lines=$(echo "$input" | wc -l)
  local index=$(((\$RANDOM % $n_lines) + 1))
  echo "$input" | sed -n "${index}p"
}

# Succeeds with the probability N% (0-100)
run_with_probability() {
  [ $(($RANDOM % 100)) -lt $1 ]
}

echo_with_probability() {
  if run_with_probability $1
  then
    cat
  fi
}


#=============================================================
# Initialize list of search queries
query=''
keywords=''
keywords_matcher=''
if [ "$WATCH_KEYWORDS" != '' ]
then
  query="$(echo "$WATCH_KEYWORDS" |
    $esed -e "s/^[$whitespaces]*,[$whitespaces]*|[$whitespaces]*,[$whitespaces]*$//g" \
          -e "s/[$whitespaces]*,[$whitespaces]*/ OR /g" \
          -e "s/^[$whitespaces]*OR[$whitespaces]+|[$whitespaces]+OR[$whitespaces]*$//g")"
  keywords="$(echo ",$WATCH_KEYWORDS," |
    $esed -e "s/^[$whitespaces]*,[$whitespaces]*|[$whitespaces]*,[$whitespaces]*$//g" \
          -e "s/[$whitespaces]*,+[$whitespaces]*/,/g" \
          -e 's/^,|,$//g')"
  keywords_matcher="$(echo "$WATCH_KEYWORDS" |
    $esed -e "s/^[$whitespaces]*,[$whitespaces]*|[$whitespaces]*,[$whitespaces]*$//g" \
          -e "s/[$whitespaces]*,+[$whitespaces]*/|/g" \
          -e 's/^\||\|$//g')"
fi
