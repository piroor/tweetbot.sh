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

  export MY_SCREEN_NAME
  export MY_LANGUAGE
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
logmodule="$TWEET_LOGMODULE"
logdate_format='%Y-%m-%d %H:%M:%S'

log() {
  local logmodule_part=''
  [ "$logmodule" != '' ] && logmodule_part=" $logmodule:"
  local message="[$(date +"$logdate_format")]$logmodule_part $*"
  echo "$message" 1>&2
  echo "$message" >> "$logfile"
}

debug() {
  [ "$TWEETBOT_DEBUG" = '' ] && return 0
  local logmodule_part=''
  [ "$logmodule" != '' ] && logmodule_part=" $logmodule:"
  local message="[$(date +"$logdate_format")]$logmodule_part $*"
  echo "$message" 1>&2
  echo "$message" >> "$logfile"
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
monologue_selector="$TWEET_BASE_DIR/monologue_selector.sh"

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

monologues_dir="$TWEET_BASE_DIR/monologues"
mkdir -p "$monologues_dir"


# default personality

FOLLOW_ON_FOLLOWED=true
FOLLOW_ON_MENTIONED=true
FOLLOW_ON_QUOTED=true
FOLLOW_ON_RETWEETED=false

SPAM_USER_PATTERN='follow *(back|me)'

FAVORITE_MENTIONS=true
FAVORITE_QUOTATIONS=true
FAVORITE_SEARCH_RESULTS=true

RETWEET_MENTIONS=false
RETWEET_QUOTATIONS=true
RETWEET_SEARCH_RESULTS=true

RESPOND_TO_MENTIONS=true
RESPOND_TO_QUOTATIONS=true
RESPOND_TO_SEARCH_RESULTS=true

TIMELY_TOPIC_PROBABILITY=20
FREQUENCY_OF_CAPRICES=66
NEW_TOPIC=66
CONVERSATION_PERSISTENCE=40

MAX_BODY_CACHE=1000
ADMINISTRATORS=''
WATCH_KEYWORDS=''
AUTO_FOLLOW_QUERY=''
MONOLOGUE_INTERVAL_MINUTES=60
MONOLOGUE_TIME_SPAN="morning/06:00-07:00 \
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

whitespaces=' \f\n\r\t　'
non_whitespaces='[^ \f\n\r\t　]'

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
  local created_at="$(echo "$tweet" | jq -r .created_at | date -f - +%s)"
  local now=$(date +%s)
  [ $((now - created_at)) -gt $expire_seconds ]
}

is_protected_tweet() {
  cat | jq -r .user.protected | grep 'true' > /dev/null
}

is_protected_user() {
  cat | jq -r .protected | grep 'true' > /dev/null
}

is_spam_like_user() {
  local user="$(cat)"

  local spam_level=0

  if [ "$(echo "$user" | jq -r .default_profile)" = 'true' ]
  then
    log " => default profile"
    spam_level=$(($spam_level + 1))
  fi

  if [ "$(echo "$user" | jq -r .default_profile_image)" = 'true' ]
  then
    log " => default icon"
    spam_level=$(($spam_level + 1))
  fi

  local created_at="$(echo "$user" | jq -r .created_at | date -f - +%s)"
  local now=$(date +%s)
  local one_year_in_seconds=$((365 * 24 * 60 * 60))
  if [ $((now - created_at)) -lt $one_year_in_seconds ]
  then
    log " => recently created"
    spam_level=$(($spam_level + 1))
  fi

  local count="$(echo "$user" | jq -r .statuses_count)"
  if [ $count -lt 100 ]
  then
    log " => too less tweets ($count < 100)"
    spam_level=$(($spam_level + 1))
  fi

  local description="$(echo "$user" | jq -r .description)"
  if [ "$description" = '' ]
  then
    log " => no description"
    spam_level=$(($spam_level + 1))
  fi

  if echo "$description" | egrep "$SPAM_USER_PATTERN" > /dev/null
  then
    log " => matched to the spam pattern"
    spam_level=$(($spam_level + 1))
  fi

  if [ $spam_level -ge 2 ]
  then
    log " => spam level $spam_level: this account is detected as a spam."
    return 0
  fi

  return 1
}

is_reply() {
  local replied_id="$(jq -r .in_reply_to_status_id_str)"
  [ "$replied_id" != 'null' -a "$replied_id" != '' ]
}

other_replied_people() {
  cat |
    $esed -e "s/^((@[^$whitespaces]+[$whitespaces]+)+)?.*/\1/" \
          -e "s/@${MY_SCREEN_NAME}[$whitespaces]+//"
}

follow_owner() {
  local tweet="$(cat)"
  local id="$(echo "$tweet" | jq -r .id_str)"
  local owner="$(echo "$tweet" | jq -r .user.screen_name)"

  log "Trying to follow to the owner of $id, $owner..."

  user="$(echo "$tweet" | jq -c .user)"

  if echo "$user" | is_protected_user
  then
    log " => protected user should not be followed to avoid privacy issues"
    return 0
  fi

  if echo "$user" | is_spam_like_user
  then
    log " => spam like user should not be followed"
    return 0
  fi

  if echo "$tweet" | jq -r .user.following | grep "false" > /dev/null
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

  if echo "$tweet" | jq -r .favorited | grep "false" > /dev/null
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

  if echo "$tweet" | jq -r .retweeted | grep "false" > /dev/null
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
  [ -f "$already_replied_dir/$id" -a "$FORCE_PROCESS" != 'yes' ]
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

  if is_already_replied "$id"
  then
    log '  => already replied'
    return 1
  fi

  log "Sending replies to $id..."
  cat | post_sequential_tweets "$id"
  return $?
}

post_sequential_tweets() {
  local previous_id="$1"
  local result
  while read -r body
  do
    if [ "$previous_id" != '' ]
    then
      result="$("$tweet_sh" reply "$previous_id" "$body")"
    else
      result="$("$tweet_sh" post "$body")"
    fi

    if [ $? = 0 ]
    then
      on_replied "$previous_id"
      previous_id="$(echo "$result" | jq -r .id_str)"
      echo "$body" | cache_body "$previous_id"
      log '  => successfully posted'
    else
      log '  => failed to post'
      log "     result: $result"
      return 1
    fi
  done
  return 0
}

post_quotation() {
  local owner=$1
  local id=$2
  local url="https://twitter.com/$owner/status/$id"

  if is_already_replied "$id"
  then
    log '  => already replied'
    return 1
  fi

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
# Misc.

try_lock() {
  local name="$1"
  mkdir "$status_dir/lock.$name" 2> /dev/null
}

try_lock_until_success() {
  local name="$1"
  while true
  do
    try_lock "$name" && break
    sleep 1s
  done
}

unlock() {
  local name="$1"
  [ "$name" = '' ] && return 0
  rm -rf "$status_dir/lock.$name"
}

clear_all_lock() {
  (cd $status_dir &&
    rm -rf lock.*)
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
