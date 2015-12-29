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


me="$("$tools_dir/tweet.sh/tweet.sh" showme)"
my_screen_name="$(echo "$me" | jq -r .screen_name | tr -d '\n')"
lang="$(echo "$me" | jq -r .lang | tr -d '\n')"
if [ "$lang" = 'null' -o "$lang" = '' ]
then
  lang="en"
fi

echo " my screen name: $my_screen_name" 1>&2
echo " lang          : $lang" 1>&2

export TWEET_SCREEN_NAME="$my_screen_name"
COMMON_ENV="env TWEET_SCREEN_NAME=\"$TWEET_SCREEN_NAME\" TWEET_BASE_DIR=\"$TWEET_BASE_DIR\""

queries_file="$TWEET_BASE_DIR/queries.txt"
queries=''
keywords=''
if [ -f "$queries_file" ]
then
  echo "Reading search queries from \"$queries_file\"" 1>&2
  queries="$( \
    # first, convert CR+LF => LF
    nkf -Lu "$queries_file" |
    # ignore non-CJK quieries - they can be tracked via "keywords".
    egrep -i -v '^[!-~]+$' |
    egrep -v '^\s*$' |
    sed 's/$/ OR /' |
    tr -d '\n' |
    sed 's/ OR $//')"
  keywords="$( \
    # first, convert CR+LF => LF
    nkf -Lu "$queries_file" |
    # ignore CJK quieries
    egrep -i '^[!-~]+$' |
    egrep -v '^\s*$' |
    paste -s -d ',')"
fi


self_pid=$$
trap 'kill_descendants $self_pid; exit 0' HUP INT QUIT KILL TERM


# Sub process 1: watching mentions with the streaming API

"$tools_dir/tweet.sh/tweet.sh" watch-mentions \
  -k "$keywords" \
  -m "$COMMON_ENV $tools_dir/handle_mention.sh" \
  -r "$COMMON_ENV $tools_dir/handle_retweet.sh" \
  -q "$COMMON_ENV $tools_dir/handle_quotation.sh" \
  -f "$COMMON_ENV $tools_dir/handle_follow.sh" \
  -d "$COMMON_ENV $tools_dir/handle_dm.sh" \
  -s "$COMMON_ENV $tools_dir/handle_search_result.sh" \
  &


# Sub process 2: watching search results with polling of the REST search API

periodical_search() {
  echo " queries: $queries" 1>&2

  count=100
  last_id=''
  keywords_for_search_results="$(echo "$queries" | sed 's/ OR /,/g')"

  while true
  do
    while read -r tweet
    do
      id="$(echo "$tweet" | jq -r .id_str)"
      if [ "$last_id" = '' ]
      then
        last_id="$id"
      fi
      if [ $id -gt $last_id ]
      then
        last_id="$id"
      fi
      handle_mentions "$my_screen_name" \
        -k "$keywords_for_search_results" \
        -m "$COMMON_ENV $tools_dir/handle_mention.sh" \
        -r "$COMMON_ENV $tools_dir/handle_retweet.sh" \
        -q "$COMMON_ENV $tools_dir/handle_quotation.sh" \
        -f "$COMMON_ENV $tools_dir/handle_follow.sh" \
        -d "$COMMON_ENV $tools_dir/handle_dm.sh" \
        -s "$COMMON_ENV $tools_dir/handle_search_result.sh"
      sleep 3s
    done < <("$tools_dir/tweet.sh/tweet.sh" search \
                -q "$queries" \
                -l "$lang" \
                -c "$count" \
                -s "$last_id" |
                jq -c '.statuses[]')
    sleep 5m
    # increment "since id" to bypass cached search results
    last_id="$(($last_id + 1))"
  done
}
[ "$queries" != '' ] && periodical_search &


wait
