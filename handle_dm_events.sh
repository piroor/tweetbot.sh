#!/usr/bin/env bash

tools_dir="$(cd "$(dirname "$0")" && pwd)"
source "$tools_dir/handle_dm_common.sh"

lock_key=''

while unlock "$lock_key" && read -r event
do
  sender_id="$(echo "$event" | jq -r .message_create.sender_id)"
  sender="$(get_screen_name "$sender_id")"
  id="$(echo "$event" | jq -r .id)"

  lock_key="dm.$id"
  try_lock_until_success "$lock_key"

  log '=============================================================='
  log "DM $id from $sender ($sender_id)"

  if [ "$sender_id" = "$MY_USER_ID" ]
  then
    log " => ignored, because this is my activity"
    continue
  fi

  if echo "$event" | expired_by_seconds $((60 * 60 * 24))
  then
    log " => ignored, because this is sent 24 hours or more ago"
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

  all_body="$(echo "$event" | jq -r .message_create.message_data.text)"
  log " all_body: $all_body"

  echo "$all_body" |
    while read body
    do
      command_name="$(echo "$body" | sed -E "s/^([^ ]+).*$/\1/")"
      log "command name = $command_name"
      log "command body = $body"
      case "$command_name" in
        run )
          run_user_defined_command "$sender_id" "$body"
          ;;
        echo )
          do_echo "$sender_id" "$body"
          ;;
        test )
          test_response "$sender_id" "$body"
          ;;
        +res*|-res* )
          modify_response "$sender_id" "$body"
          ;;
        +*|-* )
          modify_monologue "$sender_id" "$body"
          ;;
        'tweet!'|'post!' )
          body="$(echo "$body" | remove_first_arg)"
          post "$sender_id" "$body"
          ;;
        tweet|post )
          body="$(echo "$body" | remove_first_arg)"
          queue="post $body"
          echo "$queue" > "$command_queue_dir/$id.post"
          echo "dm $sender_id Queued command is processed: \"$queue\"" \
            >> "$command_queue_dir/$id.post"
          log "Command queued: \"$queue\""
          respond "$sender_id" "Command queued: \"$queue\""
          ;;
        reply )
          reply_to "$sender_id" "$body"
          ;;
        'rt!'|'retweet!' )
          body="$(echo "$body" | remove_first_arg)"
          process_generic_command "$sender_id" "retweet $body"
          ;;
        rt|retweet )
          body="$(echo "$body" | remove_first_arg)"
          queue="retweet $body"
          echo "$queue" > "$command_queue_dir/$id.retweet"
          echo "dm $sender_id Queued command is processed: \"$queue\"" \
            >> "$command_queue_dir/$id.retweet"
          log "Command queued: \"$queue\""
          respond "$sender_id" "Command queued: \"$queue\""
          ;;
        'favrt!'|'rtfav!'|'fr!'|'rf!'|'fav_and_rt!' )
          body="$(echo "$body" | remove_first_arg)"
          process_generic_command "$sender_id" "favorite $body"
          process_generic_command "$sender_id" "retweet $body"
          ;;
        favrt|rtfav|fr|rf|fav_and_rt )
          body="$(echo "$body" | remove_first_arg)"
          echo "favorite $body" > "$command_queue_dir/$id.retweet"
          echo "retweet $body" >> "$command_queue_dir/$id.retweet"
          echo "dm $sender_id Queued command is processed: \"fav and rt $body\"" \
            >> "$command_queue_dir/$id.retweet"
          log "Command queued: \"fav and rt $body\""
          respond "$sender_id" "Command queued: \"fav and rt $body\""
          ;;
        del*|rem* )
          process_generic_command "$sender_id" "$body"
          ;;
        unrt|unretweet|fav*|unfav*|follow|unfollow )
          delete_queued_command_for "$(echo "$body" | remove_first_arg)"
          process_generic_command "$sender_id" "$body"
          ;;
        search-result )
          handle_search_result "$sender_id" "$body"
          ;;
      esac
      log "one message body is processed."
    done

  on_dm_processed "$id"
done
