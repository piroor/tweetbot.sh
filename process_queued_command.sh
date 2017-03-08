#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
source "$tools_dir/common.sh"
logfile="$log_dir/process_queued_command.log"

lock_key=''

while unlock "$lock_key" && read path
do
  commands="$(cat "$path")"
  id="$(basename "$path" | cut -d '.' -f 1)"

  lock_key="queued_commands.$(basename "$path")"
  try_lock_until_success "$lock_key"

  log '=============================================================='
  log 'Processing queued commands:'
  log "$(echo "$commands" | sed 's/^/  /')"

  processed='false'
  failed='false'
  while read command
  do
    output="$("$tweet_sh" $command 2>&1)"
    if [ $? = 0 ]
    then
      log "Successfully processed: \"$command\""
      processed='true'
    else
      log "$output"
      log "Failed to process \"$command\""
      failed='true'
    fi
  done < <(echo "$commands")

  rm "$path"
  unlock "$lock_key"
  if [ "$processed" = 'true' -a "$failed" != 'true' ]
  then
    exit 0
  fi
done < <(find "$command_queue_dir" -type f | sort)

exit 1
