#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
source "$tools_dir/common.sh"
logfile="$log_dir/process_queued_search_result.log"

lock_key=''
processed_users=' '
tweeted='false'

queue_dir="$status_dir/search_result_queue"
mkdir -p "$queue_dir"

while unlock "$lock_key" && read path
do
  tweet="$(cat "$path")"

  screen_name="$(echo "$tweet" | jq -r .user.screen_name)"
  id="$(echo "$tweet" | jq -r .id_str)"
  url="https://twitter.com/$screen_name/status/$id"

  lock_key="search_result.$id"
  try_lock_until_success "$lock_key"

  log '=============================================================='
  log "Processing queued search result, tweeted by $screen_name at $url"

  if echo "$processed_users" | grep " $screen_name " > /dev/null
  then
    debug " => ignore already processed user in this loop"
    continue
  fi

  processed_path="$queue_dir/$(basename "$path" | sed 's/queued/done/')"
  mv "$path" "$processed_path"
  processed_users="$processed_users$screen_name "

  # log " => follow $screen_name"
  # "$tweet_sh" follow $screen_name > /dev/null

  if is_true "$FAVORITE_SEARCH_RESULTS"
  then
    echo "$tweet" | favorite
  fi

  is_protected=$(echo "$tweet" | is_protected_tweet && echo 1)

  # Don't RT protected user's tweet!
  if [ "$is_protected" != '1' ] && is_true "$RETWEET_SEARCH_RESULTS"
  then
    echo "$tweet" | retweet
    tweeted='true'
  fi

  # If we include the screen name into the keywords, simple mentions
  # can be detected as a search result. Even if it has been processed
  # as a mention, we should retweet it.
  if echo "$body" | sed "s/^@$me//" | egrep -i "$keywords_matcher" > /dev/null
  then
    if [ "$is_protected" != '1' ] && is_true "$RESPOND_TO_SEARCH_RESULTS"
    then
      # Don't post default questions as quotation!
      responses="$(echo "$body" | env NO_QUESTION=1 "$responder")"
      if [ $? != 0 -o "$responses" = '' ]
      then
        log " => don't quote case"
      else
        echo "$responses" |
          post_quotation "$screen_name" "$id"
        tweeted='true'
      fi
    fi
  fi

  rm "$processed_path"
done < <(find "$queue_dir" -name "queued.*" | sort)

[ "$tweeted" = 'true' ]
