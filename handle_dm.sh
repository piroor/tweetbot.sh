#!/usr/bin/env bash

tools_dir="$(cd "$(dirname "$0")" && pwd)"
source "$tools_dir/handle_dm_common.sh"

lock_key=''

while unlock "$lock_key" && read -r message
do
  sender="$(echo "$message" | jq -r .sender_screen_name)"
  id="$(echo "$message" | jq -r .id_str)"

  lock_key="dm.$id"
  try_lock_until_success "$lock_key"

  log '=============================================================='
  log "DM $id from $sender"

  if [ "$sender" = "$MY_SCREEN_NAME" ]
  then
    log " => ignored, because this is my activity"
    continue
  fi

  if echo "$message" | expired_by_seconds $((30 * 60))
  then
    log " => ignored, because this is sent 30 minutes or more ago"
    continue
  fi

  if echo "$sender" | egrep -v "$administrators" > /dev/null
  then
    log ' => not an administrator, ignore it'
    continue
  fi

  if is_already_processed_dm "$id"
  then
    log ' => already processed, ignore it'
    continue
  fi

  body="$(echo "$message" | "$tweet_sh" body)"
  log " body    : $body"

  command_name="$(echo "$body" | $esed "s/^([^ ]+).*$/\1/")"
  log "command name = $command_name"
  case "$command_name" in
    run )
      run_user_defined_command "$sender" "$body"
      ;;
    echo )
      do_echo "$sender" "$body"
      ;;
    test )
      test_response "$sender" "$body"
      ;;
    +res*|-res* )
      modify_response "$sender" "$body"
      ;;
    +*|-* )
      modify_monologue "$sender" "$body"
      ;;
    'tweet!'|'post!' )
      body="$(echo "$body" | remove_first_arg)"
      post "$sender" "$body"
      ;;
    tweet|post )
      body="$(echo "$body" | remove_first_arg)"
      queue="post $body"
      echo "$queue" > "$command_queue_dir/$id.post"
      echo "dm $sender Queued command is processed: \"$queue\"" \
        >> "$command_queue_dir/$id.post"
      log "Command queued: \"$queue\""
      respond "$sender" "Command queued: \"$queue\""
      ;;
    reply )
      reply_to "$sender" "$body"
      ;;
    'rt!'|'retweet!' )
      body="$(echo "$body" | remove_first_arg)"
      process_generic_command "$sender" "retweet $body"
      ;;
    rt|retweet )
      body="$(echo "$body" | remove_first_arg)"
      queue="retweet $body"
      echo "$queue" > "$command_queue_dir/$id.retweet"
      echo "dm $sender Queued command is processed: \"$queue\"" \
        >> "$command_queue_dir/$id.retweet"
      log "Command queued: \"$queue\""
      respond "$sender" "Command queued: \"$queue\""
      ;;
    'favrt!'|'rtfav!'|'fr!'|'rf!' )
      body="$(echo "$body" | remove_first_arg)"
      process_generic_command "$sender" "favorite $body"
      process_generic_command "$sender" "retweet $body"
      ;;
    favrt|rtfav|fr|rf )
      body="$(echo "$body" | remove_first_arg)"
      echo "favorite $body" > "$command_queue_dir/$id.retweet"
      echo "retweet $body" >> "$command_queue_dir/$id.retweet"
      echo "dm $sender Queued command is processed: \"fav and rt $body\"" \
        >> "$command_queue_dir/$id.retweet"
      log "Command queued: \"fav and rt $body\""
      respond "$sender" "Command queued: \"fav and rt $body\""
      ;;
    del*|rem* )
      process_generic_command "$sender" "$body"
      ;;
    unrt|unretweet|fav*|unfav*|follow|unfollow )
      delete_queued_command_for "$(echo "$body" | remove_first_arg)"
      process_generic_command "$sender" "$body"
      ;;
    search-result )
      handle_search_result "$sender" "$body"
      ;;
  esac

  on_dm_processed "$id"
done
