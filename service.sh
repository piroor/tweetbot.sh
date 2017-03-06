#!/usr/bin/env bash

tools_dir="$TWEETBOT_DIR"
if [ "$tools_dir" = '' ]
then
  tools_dir="$(cd "$(dirname "$0")" && pwd)"
fi

data_dir="$DATA_DIR"
if [ "$data_dir" = '' ]
then
  data_dir="$(cd "$(dirname "$0")" && pwd)"
fi

pidfile="$PID_FILE"
if [ "$pidfile" = '' ]
then
  pidfile="/tmp/.tweetbot.pidfile"
fi

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
