#!/usr/bin/env bash

tools_dir="$TWEETBOT_DIR"
data_dir="$DATA_DIR"
pidfile="$PID_FILE"

cd "$data_dir"

if [ -f "$pidfile" ]
then
  pid="$(cat "$pidfile")"
  kill "$pid"
  rm "$pidfile"
fi

if [ "$1" != 'stop' ]
then
  #export TWEETBOT_DEBUG=1
  "$tools_dir/tweetbot.sh/watch.sh" &
  echo "$!" > "$pidfile"
fi
