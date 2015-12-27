#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
tweet_sh="$tools_dir/tweet.sh/tweet.sh"

source "$tweet_sh"
load_keys

log() {
  echo "$*" 1>&2
}

if [ "$TWEET_BASE_DIR" != '' ]
then
  TWEET_BASE_DIR="$(cd "$TWEET_BASE_DIR" && pwd)"
else
  TWEET_BASE_DIR="$work_dir"
fi

responses_dir="$TWEET_BASE_DIR/responses"

mkdir -p "$responses_dir"


input="$(cat)"
# add filename-or-keyword(>(alias))?(:(response))?

log 'Adding new keyword definition...'

keyword="$(echo "$input" |
  $esed -e 's/^add\s+//i' \
        -e 's/\s*(>[^:]+)?(:.*)?$//')"
alias=''
if echo "$input" | egrep "s/^add\s+[^>]+>[^:]+" > /dev/null
then
  alias="$(echo "$input" |
    $esed -e 's/^add\s+[^>]+>\s*//i' \
          -e 's/\s*(:.*)?$//')"
fi
response="$(echo "$input" |
  $esed -e 's/^add\s+[^>]+(>[^:]+)?:\s*//i')"

log "  keyword : $keyword"
log "  alias   : $alias"
log "  response: $response"

if [ "$keyword" = '' ]
then
  log "ERROR: No keyword is given."
  exit 1
fi


add_definition() {
  local path=$1
  local alias=$2
  local response=$3

  log "Adding new response to $path..."

  if [ "$alias" != '' ]
  then
    if egrep "^#\s*${alias}\s*$" "$path" > /dev/null
    then
      : # found
    else
      log "Adding new alias \"$alias\" for \"$keyword\"..."
      echo "# $alias" >> "$path"
    fi
  fi

  if [ "$response" != '' ]
  then
    if egrep "^\s*${response}\s*$" "$path" > /dev/null
    then
      : # found
    else
      log "Adding new response \"$response\"..."
      echo "$response" >> "$path"
    fi
  fi

  if [ $? = 0 ]
  then
    log 'Successfully added.'
    "$tools_dir/generate_responder.sh"
    return 0
  else
    log 'Failed to add.'
    return 1
  fi
}

# if there is any file including the keyword in its name, then reuse it.
find "$responses_dir" -type f -name "*${keyword}*" | while read path
do
  add_definition "$path" "$alias" "$response"
  exit $?
done

# if there is any file including the keyword in its keyword definitions, then reuse it.
egrep -r "^#\s*${keyword}\s*$" "$responses_dir" | cut -d ':' -f 1 | while read path
do
  add_definition "$path" "$alias" "$response"
  exit $?
done

# otherwise, create new definition file.
path="$responses_dir/autoadd_${keyword}.txt"
echo "# $keyword" > "$path"
add_definition "$path" "$alias" "$response"
exit $?
