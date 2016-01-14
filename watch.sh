#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
source "$tools_dir/common.sh"

if [ ! -f "$TWEET_BASE_DIR/tweet.client.key" ]
then
  log "FATAL ERROR: Missing key file at $TWEET_BASE_DIR/tweet.client.key"
  exit 1
fi

"$tools_dir/generate_responder.sh"
"$tools_dir/generate_monologue_selector.sh"


# Initialize required informations to call APIs

me="$("$tools_dir/tweet.sh/tweet.sh" showme)"
my_screen_name="$(echo "$me" | jq -r .screen_name | tr -d '\n')"
lang="$(echo "$me" | jq -r .lang | tr -d '\n')"
if [ "$lang" = 'null' -o "$lang" = '' ]
then
  lang="en"
fi

log " my screen name: $my_screen_name"
log " lang          : $lang"

export TWEET_SCREEN_NAME="$my_screen_name"

if [ "$WATCH_KEYWORDS" != '' ]
then
  log "Search queries from \"$WATCH_KEYWORDS\":"
  log "  query for REST searc : $query"
  log "  keywords for tracking: $keywords"
  log "  search result matcher: $keywords_matcher"
fi

# Kill all forked children always!
# Ctrl-C sometimes fails to kill descendant processes,
# so we have to use custom "kill_descendants" function...
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
self_pid=$$
trap 'kill_descendants $self_pid; clear_all_lock; exit 0' HUP INT QUIT KILL TERM


# Sub process 1: watching mentions with the streaming API

COMMON_ENV="env TWEET_SCREEN_NAME=\"$TWEET_SCREEN_NAME\" TWEET_BASE_DIR=\"$TWEET_BASE_DIR\" TWEET_LOGMODULE='streaming'"
"$tools_dir/tweet.sh/tweet.sh" watch-mentions \
  -k "$keywords" \
  -m "$COMMON_ENV $tools_dir/handle_mention.sh" \
  -r "$COMMON_ENV $tools_dir/handle_retweet.sh" \
  -q "$COMMON_ENV $tools_dir/handle_quotation.sh" \
  -f "$COMMON_ENV $tools_dir/handle_follow.sh" \
  -d "$COMMON_ENV $tools_dir/handle_dm.sh" \
  -s "$COMMON_ENV $tools_dir/handle_search_result.sh" \
  &


# Sub process 2: polling for the REST search API
#   This is required, because not-mention CJK tweets with keywords
#   won't appear in the stream tracked by "watch-mentions" command.
#   For more details of this limitation, see also:
#   https://dev.twitter.com/streaming/overview/request-parameters#track

periodical_search() {
  logmodule='search'
  local count=100
  local last_id_file="$status_dir/last_search_result"
  local last_id=''
  [ -f "$last_id_file" ] && last_id="$(cat "$last_id_file")"
  local keywords_for_search_results="$(echo "$query" | sed 's/ OR /,/g')"
  local id
  local owner
  local type
  if [ "$last_id" != '' ]
  then
    log "Doing search for newer than $last_id"
  fi

  while true
  do
    debug 'Processing results of REST search API...'
    while read -r tweet
    do
      [ "$tweet" = '' ] && continue
      id="$(echo "$tweet" | jq -r .id_str)"
      owner="$(echo "$tweet" | jq -r .user.screen_name)"
      debug "New search result detected: https://twitter.com/$owner/status/$id"
      [ "$id" = '' -o "$id" = 'null' ] && continue
      [ "$last_id" = '' ] && last_id="$id"
      if [ $id -gt $last_id ]
      then
        last_id="$id"
        echo "$last_id" > "$last_id_file"
      fi
      type="$(echo "$tweet" |
                "$tools_dir/tweet.sh/tweet.sh" type \
                  -s "$my_screen_name" \
                  -k "$keywords_for_search_results")"
      debug "   type: $type"
      debug "Processing $id as $type..."
      case "$type" in
        mention )
          echo "$tweet" |
            env TWEET_LOGMODULE='search' "$tools_dir/handle_mention.sh"
          ;;
        retweet )
          echo "$tweet" |
            env TWEET_LOGMODULE='search' "$tools_dir/handle_retweet.sh"
          ;;
        quotation )
          echo "$tweet" |
            env TWEET_LOGMODULE='search' "$tools_dir/handle_quotation.sh"
          ;;
        search-result )
          echo "$tweet" |
            env TWEET_LOGMODULE='search' "$tools_dir/handle_search_result.sh"
          ;;
      esac
      sleep 3s
    done < <("$tools_dir/tweet.sh/tweet.sh" search \
                -q "$query" \
                -l "$lang" \
                -c "$count" \
                -s "$last_id" |
                jq -c '.statuses[]' |
                tac)
    if [ "$last_id" != '' ]
    then
      # increment "since id" to bypass cached search results
      last_id="$(($last_id + 1))"
      echo "$last_id" > "$last_id_file"
    fi
    sleep 2m
  done
}
if [ "$query" != '' ]
then
  log "Tracking search results with the query \"$query\"..."
  periodical_search &
else
  log "No search queriy."
fi


# Sub process 3: polling for the REST direct messages API
#   This is required, because some direct messages can be dropped
#   in the stream.

periodical_fetch_direct_messages() {
  logmodule='dm'
  local count=100
  local last_id_file="$status_dir/last_fetched_dm"
  local last_id=''
  [ -f "$last_id_file" ] && last_id="$(cat "$last_id_file")"
  local id
  if [ "$last_id" != '' ]
  then
    log "Fetching for newer than $last_id"
  fi

  while true
  do
    debug 'Processing results of REST direct messages API...'
    while read -r message
    do
      [ "$message" = '' ] && continue
      id="$(echo "$message" | jq -r .id_str)"
      debug "New DM detected: $id"
      [ "$id" = '' -o "$id" = 'null' ] && continue
      [ "$last_id" = '' ] && last_id="$id"
      if [ $id -gt $last_id ]
      then
        last_id="$id"
        echo "$last_id" > "$last_id_file"
      fi
      echo "$message" |
        env TWEET_LOGMODULE='dm' "$tools_dir/handle_dm.sh"
      sleep 3s
    done < <("$tools_dir/tweet.sh/tweet.sh" fetch-direct-messages \
                -c "$count" \
                -s "$last_id" |
                jq -c '.[]' |
                tac)
    [ "$last_id" != '' ] && echo "$last_id" > "$last_id_file"
    sleep 1m
  done
}
periodical_fetch_direct_messages &


# Sub process 4: posting monologue tweets
# ・計算の始点は00:00
# ・指定間隔の1/3か10分の短い方を、「投稿時間の振れ幅」とする。
#   30分間隔なら、振れ幅は10分。00:25から00:35の間のどこかで投稿する。
# ・指定間隔ちょうどを90％、振れ幅最大の時を10％として、その確率で投稿する。
# ・その振れ幅の中のどこかで投稿済みであれば、その振れ幅の中では多重投稿はしない。
# ・ただし、振れ幅の最後のタイミングでまだ投稿されていなければ、必ず投稿する。

# minimum interval = 10minutes
[ $MONOLOGUE_INTERVAL_MINUTES -le 10 ] && MONOLOGUE_INTERVAL_MINUTES=10

period_span=$(( $MONOLOGUE_INTERVAL_MINUTES / 3 ))
[ $period_span -gt 10 ] && period_span=10
max_lag=$(( $period_span / 2 ))
half_interval=$(( $MONOLOGUE_INTERVAL_MINUTES / 2 ))

abs() {
  echo "sqrt($1 ^ 2)" | bc
}

calculate_monologue_probability() {
  local target_minutes=$1

  # 目標時刻から何分ずれているかを求める
  local lag=$(($target_minutes % $MONOLOGUE_INTERVAL_MINUTES))
  # 目標時刻からのずれがhalf_intervalを超えている場合、目標時刻より手前方向のずれと見なす
  [ $lag -gt $half_interval ] && lag=$(($MONOLOGUE_INTERVAL_MINUTES - $lag))

  local probability=$(( (($max_lag - $lag) * 100 / $max_lag) * 80 / 100 + 10 ))
  if [ $probability -lt 10 ]
  then
    echo 0
  else
    echo $probability
  fi
}

periodical_monologue() {
  logmodule='monologue'
  local last_post_file="$status_dir/last_monologue"
  local last_post=''
  [ -f "$last_post_file" ] && last_post=$(cat "$last_post_file")

  local process_interval=1m
  local one_day_in_minutes=$(( 24 * 60 ))

  while true
  do
    debug 'Processing monologue...'

    local current_minutes=$(time_to_minutes $(date +%H:%M))
    debug "  $current_minutes minutes past from 00:00"

    # 同じ振れ幅の中で既に投稿済みだったなら、何もしない
    if [ "$last_post" != '' ]
    then
      local delta=$(($current_minutes - $last_post))
      debug "  delta from $last_post: $delta"
      if [ $delta -lt 0 ]
      then
        delta=$(( $one_day_in_minutes - $last_post + $current_minutes ))
        debug "  delta => $delta"
      fi
      if [ $delta -le $period_span ]
      then
        debug 'Already posted in this period.'
        sleep $process_interval
        continue
      fi
    fi

    # 振れ幅の最後のタイミングかどうかを判定
    lag=$(($current_minutes % $MONOLOGUE_INTERVAL_MINUTES))
    if [ $lag -eq $max_lag ]
    then
      debug "Nothing was posted in this period."
      probability=100
    else
      probability=$(calculate_monologue_probability $current_minutes)
    fi

    debug "Posting probability: $probability %"
    if run_with_probability $probability
    then
      debug "Let's post!"
      local body="$("$monologue_selector")"
      log "Posting monologue tweet: $body"
      local result="$("$tweet_sh" post "$body")"
      if [ $? = 0 ]
      then
        log '  => successfully posted'
        id="$(echo "$result" | jq -r .id_str)"
        echo "$body" | cache_body "$id"
      else
        log '  => failed to post'
        log "     result: $result"
      fi
      last_post=$current_minutes
      echo $current_minutes > "$last_post_file"
    fi

    sleep $process_interval
  done
}
periodical_monologue &


wait
