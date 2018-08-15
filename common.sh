#!/usr/bin/env bash

#=============================================================
# Initialization

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
tweet_sh="$tools_dir/tweet.sh/tweet.sh"

detect_client_key_file() {
  local loaded_key=''
  while read path
  do
    if [ -f "$path" ]
    then
      loaded_key="$(source "$path"; echo "$CONSUMER_KEY")"
      if [ "$loaded_key" != '' ]
      then
        echo "$path"
        return 0
      fi
    fi
  done < <(cat << FIN
$work_dir/tweet.client.key
$HOME/.tweet.client.key
$tools_dir/tweet.client.key
FIN
  )
  echo ''
}

load_keys() {
  if [ "$CONSUMER_KEY" = '' ]
  then
    local path="$(detect_client_key_file)"
    echo "Using client key at $path" 1>&2
    source "$path"
  fi

  export MY_SCREEN_NAME
  export MY_USER_ID
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

command_queue_dir="$status_dir/command_queue"
mkdir -p "$command_queue_dir"

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
RESPOND_TO_SIDE_MENTIONS=false
RESPOND_TO_MULTIPLE_TARGETS_REPLY=false
RESPOND_TO_QUOTATIONS=true
RESPOND_TO_SEARCH_RESULTS=true

TIMELY_TOPIC_PROBABILITY=20
FREQUENCY_OF_CAPRICES=66
NEW_TOPIC=66
CONVERSATION_PERSISTENCE=40

MENTION_LIMIT_PERIOD_MIN=120
MAX_MENTIONS_IN_PERIOD=10

MAX_BODY_CACHE=1000
ADMINISTRATORS=''
WATCH_KEYWORDS=''
AUTO_FOLLOW_QUERY=''
PROCESS_QUEUE_INTERVALL_MINUTES=10
ACTIVE_TIME_RANGE="11:40-15:00,17:00-24:00"
MONOLOGUE_INTERVAL_MINUTES=60
MONOLOGUE_ACTIVE_TIME_RANGE="00:00-00:30,06:00-24:00"
MONOLOGUE_TIME_RANGE_GROUPS="morning/06:00-07:00 \
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

is_false() {
  if is_true "$1"
  then
    return 1
  else
    return 0
  fi
}

time_to_minutes() {
  local hours minutes
  read hours minutes <<< "$(cat | $esed 's/^0?([0-9]+):0?([0-9]+)$/\1 \2/')"
  echo $(( $hours * 60 + $minutes ))
}

is_in_time_range() {
  local time_ranges="$1"
  local now=$2

  [ "$now" = '' ] && now="$(date +%H:%M)"
  now=$(echo "$now" | time_to_minutes)

  local time_range
  local start
  local end
  for time_range in $(echo "$time_ranges" | sed 's/,/ /g')
  do
    start="$(echo "$time_range" | cut -d '-' -f 1 | time_to_minutes)"
    end="$(echo "$time_range" | cut -d '-' -f 2 | time_to_minutes)"
    [ $now -ge $start -a $now -le $end ] && return 0
  done
  return 1
}

is_not_in_time_range() {
  if is_in_time_range "$@"
  then
    return 1
  else
    return 0
  fi
}

#=============================================================
# Utilities to operate tweet JSON strings

abs() {
  echo "sqrt($1 ^ 2)" | bc
}

expired_by_seconds() {
  local expire_seconds=$1
  # tweet
  local created_at="$(cat | jq -r .created_at)"
  # event
  if [ "$created_at" = '' ]
  then
    created_at="$(cat | jq -r .created_timestamp)"
  fi
  created_at="$(echo "$created_at" | date -f - +%s)"
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

  local screen_name="$(echo "$user" | jq -r .screen_name)"
  local description="$(echo "$user" | jq -r .description)"
  if [ "$description" = '' ]
  then
    log " => no description"
    spam_level=$(($spam_level + 1))
  fi

  if echo "@$screen_name $description" | egrep "$SPAM_USER_PATTERN" > /dev/null
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
    if is_in_time_range "$ACTIVE_TIME_RANGE"
    then
      result="$("$tweet_sh" retweet $id)"
      if [ $? != 0 ]
      then
        log '  => failed to retweet'
        log "     result: $result"
      fi
    else
      local queue="retweet $id"
      echo "$queue" > "$command_queue_dir/$id.retweet"
      log " => queued: \"$queue\""
    fi
  else
    log " => already retweeted"
  fi
}

is_already_replied() {
  local id="$1"
  [ "$FORCE_PROCESS" != 'yes' ] &&
    [ "$(cd "$already_replied_dir"; find . -name "$id.*")" != '' ]
}

is_too_frequent_mention() {
  local users="$1"
  local user
  local mentions
  local all_users="$(cat | unified_users_from_body_and_args "$users")"
  for user in $all_users
  do
    user="$(echo "$user" | $esed -e 's/^@//')"
    mentions="$(cd "$already_replied_dir"; find . -name "*.$user.*" -cmin -$MENTION_LIMIT_PERIOD_MIN | wc -l)"
    if [ $mentions -gt $MAX_MENTIONS_IN_PERIOD ]
    then
      return 0
    fi
  done
  return 1
}

on_replied() {
  local id="$1"
  local users="$2"
  local all_users="$(cat | unified_users_from_body_and_args "$users")"

  touch "$already_replied_dir/$id.$(echo "$all_users" | $esed -e 's/ +/./g')."
  # remove too old files
  find "$already_replied_dir" -ctime +1 | while read path
  do
    rm -rf "$path"
  done
}

unified_users_from_body_and_args() {
  local body="$(cat)"
  cat <(echo "$body" | users_in_body) \
      <(echo "$users" | $esed -e 's/ +/\n/g' | $esed -e 's/^.*@//') | \
    sort | uniq | tr -d '\n' | paste -s -d '.'
}

users_in_body() {
  while read -r body
  do
    echo "$body" | $esed -e 's/ +/\n/g' | grep -E '^\.?@.' | $esed -e 's/^.*@//'
  done
}

post_replies() {
  local id="$1"
  local users="$2"
  local body="$(cat)"

  if is_already_replied "$id"
  then
    log '  => already replied'
    return 1
  fi

  if echo "$body" | is_too_frequent_mention "$users"
  then
    log '  => too frequent mention for same user'
    return 1
  fi

  log "Sending replies to $id..."
  echo "$body" | post_sequential_tweets "$id" "$users"
  return $?
}

post_sequential_tweets() {
  local previous_id="$1"
  local users="$2"
  local result
  while read -r body
  do
    body="$(echo "$body" | $esed -e 's/<br>/\n/g')"
    if [ "$previous_id" != '' ]
    then
      result="$(echo -e "$body" | "$tweet_sh" reply "$previous_id")"
    else
      result="$(echo -e "$body" | "$tweet_sh" post)"
    fi

    if [ $? = 0 ]
    then
      echo "$body" | on_replied "$previous_id" "$users"
      previous_id="$(echo "$result" | jq -r .id_str)"
      echo "$body" | cache_body "$previous_id"
      log '  => successfully posted'
    else
      log '  => failed to post'
      log "     result: $result"
      return 1
    fi
    sleep 10s
  done
  return 0
}

post_quotation() {
  local owner=$1
  local id=$2
  local url="https://twitter.com/$owner/status/$id"
  local bodies="$(cat)"

  if is_already_replied "$id"
  then
    log '  => already replied'
    return 1
  fi

  if is_too_frequent_mention "$owner"
  then
    log '  => too frequent mention for same user'
    return 1
  fi

  log "Quoting the tweet $id by $owner..."
  if is_in_time_range "$ACTIVE_TIME_RANGE"
  then
    local result
    echo "$bodies" | while read -r body
    do
      result="$(echo -e "$body $url" | "$tweet_sh" reply "$id")"
      if [ $? = 0 ]
      then
        log '  => successfully quoted'
        echo "$body" | on_replied "$id" "$owner"
        # send following resposnes as a sequential tweets
        id="$(echo "$result" | jq -r .id_str)"
        echo "$body $url" | cache_body "$id"
      else
        log '  => failed to quote'
        log "     result: $result"
      fi
    done
  else
    local queue_file="$command_queue_dir/$id.quote"
    touch "$queue_file"
    echo "$bodies" | while read -r body
    do
      echo "reply $id $body $url" >> "$queue_file"
    done
    log " => reactions are queued at $queue_file"
  fi
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


get_screen_name() {
  local id="$1"
  local name=''
  local cached="$(egrep ":$id$" "$status_dir/screen_name_to_user_id" 2>/dev/null | tail -n 1 | tr -d '\n')"
  if [ "$cached" != '' ]
  then
    name="$(echo -n "$(echo -n "$cached" | cut -d : -f 1)")"
    if [ "$name" != '' ]
    then
      echo -n "$name"
      return 0
    fi
  fi
  name="$("$tweet_sh" get-screen-name "$id")"
  if [ "$name" != '' ]
  then
    echo "$name:$id" >> "$status_dir/screen_name_to_user_id"
  fi
  echo -n "$name"
}

get_user_id() {
  local id=''
  local name="$1"
  local cached="$(egrep "^$name:" "$status_dir/screen_name_to_user_id" 2>/dev/null | tail -n 1 | tr -d '\n')"
  if [ "$cached" != '' ]
  then
    id="$(echo -n "$(echo -n "$cached" | cut -d : -f 2)")"
    if [ "$id" != '' ]
    then
      echo -n "$id"
      return 0
    fi
  fi
  id="$("$tweet_sh" get-user-id "$name")"
  if [ "$id" != '' ]
  then
    echo "$name:$id" >> "$status_dir/screen_name_to_user_id"
  fi
  echo -n "$id"
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

# ・計算の始点は00:00
# ・指定間隔の1/3か10分の短い方を、「投稿時間の振れ幅」とする。
#   30分間隔なら、振れ幅は10分。00:25から00:35の間のどこかで投稿する。
# ・指定間隔ちょうどを90％、振れ幅最大の時を10％として、その確率で投稿する。
# ・その振れ幅の中のどこかで投稿済みであれば、その振れ幅の中では多重投稿はしない。
# ・ただし、振れ幅の最後のタイミングでまだ投稿されていなければ、必ず投稿する。
run_periodically() {
  local interval_minutes="$1"
  local last_processed="$2"
  local active_time_range="$3"

  local period_range=$(( $interval_minutes / 3 ))
  [ $period_range -gt 10 ] && period_range=10
  local max_lag=$(( $period_range / 2 ))
  local half_interval=$(( $interval_minutes / 2 ))

  calculate_probability() {
    local target_minutes=$1

    # 目標時刻から何分ずれているかを求める
    local lag=$(($target_minutes % $interval_minutes))
    # 目標時刻からのずれがhalf_intervalを超えている場合、目標時刻より手前方向のずれと見なす
    [ $lag -gt $half_interval ] && lag=$(($interval_minutes - $lag))

    local probability=$(( (($max_lag - $lag) * 100 / $max_lag) * 80 / 100 + 10 ))
    if [ $probability -lt 10 ]
    then
      echo 0
    else
      echo $probability
    fi
  }

  local process_interval=1m
  local one_day_in_minutes=$(( 24 * 60 ))

  debug 'Initiating new periodical task...'
  debug "  interval    = $interval_minutes minutes"
  debug "  last        = $last_processed"
  debug "  active time = $active_time_range"

  while true
  do
    if [ "$active_time_range" != '' ]
    then
      if is_not_in_time_range "$active_time_range"
      then
        sleep $process_interval
        continue
      fi
    fi

    debug 'Processing periodical task...'

    local current_minutes=$(date +%H:%M | time_to_minutes)
    debug "  $current_minutes minutes past from 00:00"

    # 同じ振れ幅の中で既に投稿済みだったなら、何もしない
    if [ "$last_processed" != '' ]
    then
      local delta=$(($current_minutes - $last_processed))
      debug "  delta from $last_processed: $delta"
      if [ $delta -lt 0 ]
      then
        delta=$(( $one_day_in_minutes - $last_processed + $current_minutes ))
        debug "  delta => $delta"
      fi
      if [ $delta -le $period_range ]
      then
        debug 'Already processed in this period.'
        sleep $process_interval
        continue
      fi
    fi

    # 振れ幅の最後のタイミングかどうかを判定
    lag=$(($current_minutes % $interval_minutes))
    if [ $lag -eq $max_lag ]
    then
      debug "Nothing was processed in this period."
      probability=100
    else
      probability=$(calculate_probability $current_minutes)
    fi

    debug "Probability to process: $probability %"
    if run_with_probability $probability
    then
      debug "Let's process!"
      last_processed=$current_minutes
      echo $current_minutes
    fi

    sleep $process_interval
  done

  unset calculate_probability
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
          -e "s/^[$whitespaces]*OR[$whitespaces]+|[$whitespaces]+OR[$whitespaces]*$//g") -from:$MY_SCREEN_NAME"
  keywords="$(echo ",$WATCH_KEYWORDS," |
    $esed -e "s/^[$whitespaces]*,[$whitespaces]*|[$whitespaces]*,[$whitespaces]*$//g" \
          -e "s/[$whitespaces]*,+[$whitespaces]*/,/g" \
          -e 's/^,|,$//g')"
  keywords_matcher="$(echo "$WATCH_KEYWORDS" |
    $esed -e "s/^[$whitespaces]*,[$whitespaces]*|[$whitespaces]*,[$whitespaces]*$//g" \
          -e "s/[$whitespaces]*,+[$whitespaces]*/|/g" \
          -e 's/^\||\|$//g')"
fi
