#!/usr/bin/env bash

tools_dir="$(cd "$(dirname "$0")" && pwd)"
pidfile="/tmp/.tweetbot.pidfile"

cd "$tools_dir"

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
