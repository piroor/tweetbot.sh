#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
tweet_sh="$tools_dir/tweet.sh/tweet.sh"

if [ "$TWEET_BASE_DIR" != '' ]
then
  TWEET_BASE_DIR="$(cd "$TWEET_BASE_DIR" && pwd)"
else
  TWEET_BASE_DIR="$work_dir"
fi

if [ ! -f "$TWEET_BASE_DIR/tweet.client.key" ]
then
  echo "FATAL ERROR: Missing key file at $TWEET_BASE_DIR/tweet.client.key" 1>&2
  exit 1
fi

source "$tweet_sh"
load_keys

logs_dir="$TWEET_BASE_DIR/logs"
mkdir -p "$logs_dir"

already_replied_dir="$TWEET_BASE_DIR/already_replied"
mkdir -p "$already_replied_dir"


"$tools_dir/generate_responder.sh"


queries_file="$TWEET_BASE_DIR/queries.txt"
queries=''
keywords=''
if [ -f "$queries_file" ]
then
  echo "Reading search queries from \"$queries_file\"" 1>&2
  queries="$( \
    # first, convert CR+LF => LF
    nkf -Lu "$queries_file" |
    egrep -v '^\s*$' |
    sed 's/$/ OR /' |
    tr -d '\n' |
    sed 's/ OR $//')"
  keywords="$( \
    # first, convert CR+LF => LF
    nkf -Lu "$queries_file" |
    egrep -v '^\s*$' |
    paste -s -d ',')"
fi

mentions_handler_options="$(cat << FIN
  -k "$keywords" \
  -m "env TWEET_BASE_DIR=\"$TWEET_BASE_DIR\" $tools_dir/handle_mention.sh" \
  -r "env TWEET_BASE_DIR=\"$TWEET_BASE_DIR\" $tools_dir/handle_retweet.sh" \
  -q "env TWEET_BASE_DIR=\"$TWEET_BASE_DIR\" $tools_dir/handle_quotation.sh" \
  -f "env TWEET_BASE_DIR=\"$TWEET_BASE_DIR\" $tools_dir/handle_follow.sh" \
  -d "env TWEET_BASE_DIR=\"$TWEET_BASE_DIR\" $tools_dir/handle_dm.sh" \
  -s "env TWEET_BASE_DIR=\"$TWEET_BASE_DIR\" $tools_dir/handle_search_result.sh"
FIN
)"

"$tools_dir/tweet.sh/tweet.sh" watch-mentions $mentions_handler_options &


if [ "$queries" != '' ]
then
  me="$("$tools_dir/tweet.sh/tweet.sh" showme)"
  my_screen_name="$(echo "$me" | jq -r .screen_name | tr -d '\n')"
  lang="$(echo "$me" | jq -r .lang | tr -d '\n')"
  if [ "$lang" = 'null' -o "$lang" = '' ]
  then
    lang="en"
  fi

  count=100
  last_id=''

  while true
  do
    while read -r tweet
    do
      last_id="$(echo "$tweet" | jq -r .id_str)"
      handle_mentions "$my_screen_name" $mentions_handler_options
    done < <("$tools_dir/tweet.sh/tweet.sh" search \
                -q "$queries" \
                -l "$lang" \
                -c "$count" \
                -s "$last_id" |
                jq -c '.statuses[]')
    sleep 5m
  done
fi

wait
