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
# add filename-or-keyword(>(alias))?( +(response))?

log 'Managing keyword definitions...'

whitespaces=' \f\n\r\t@'
non_whitespaces='[^ \f\n\r\t@]'

operation="$(echo "$input" | $esed "s/^(${non_whitespaces}+)[$whitespaces].+$/\1/")"
keyword="$(echo "$input" |
  $esed -e "s/^${non_whitespaces}+[$whitespaces]+//" \
        -e "s/[$whitespaces]*(>${non_whitespaces}+)?([$whitespaces].*)?\$//")"
alias=''
if echo "$input" |
     egrep "^[^\s]+\s+[^>]+>\s*[^\s]+" > /dev/null
then
  alias="$(echo "$input" |
    $esed -e "s/^${non_whitespaces}+[$whitespaces]+[^>]+>[$whitespaces]*//" \
          -e "s/(${non_whitespaces}+)[$whitespaces]*([$whitespaces].*)?\$/\1/")"
fi
response="$(echo "$input" |
  $esed -e "s/^${non_whitespaces}+[$whitespaces]+[^>$whitespaces]+([$whitespaces]*>[$whitespaces]*${non_whitespaces}+)?[$whitespaces]*//")"

log "  operation: $operation"
log "  keyword  : $keyword"
log "  alias    : $alias"
log "  response : $response"

if [ "$keyword" = '' ]
then
  log "ERROR: No keyword is given."
  exit 1
fi


process_add_command() {
  # if there is any file including the keyword in its name, then reuse it.
  while read path
  do
    add_definition "$path" "$alias" "$response"
    exit $?
  done < <(find "$responses_dir" -type f -name "*${keyword}*")

  # if there is any file including the keyword in its keyword definitions, then reuse it.
  while read path
  do
    add_definition "$path" "$alias" "$response"
    exit $?
  done < <(egrep -r "^#\s*${keyword}\s*$" "$responses_dir" | cut -d ':' -f 1)

  # otherwise, create new definition file.
  path="$responses_dir/autoadd_${keyword}.txt"
  echo "# $keyword" > "$path"
  add_definition "$path" "$alias" "$response"
  exit $?
}

add_definition() {
  local path=$1
  local alias=$2
  local response=$3
  local modified=0

  log "Adding new response to $path..."

  # always insert new line, otherwise the added line can be
  # connected to the last existing line!
  echo "" >> "$path"

  if [ "$alias" != '' ]
  then
    if egrep "^#\s*${alias}\s*$" "$path" > /dev/null
    then
      : # found
    else
      log "Adding new alias \"$alias\" for \"$keyword\"..."
      echo "# $alias" >> "$path"
      modified=1
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
      modified=1
    fi
  fi

  if [ $? = 0 ]
  then
    if [ $modified = 0 ]
    then
      log 'Nothing to be added.'
    else
      log 'Successfully added.'
      "$tools_dir/generate_responder.sh"
    fi
    return 0
  else
    log 'Failed to add.'
    return 1
  fi
}


process_remove_command() {
  # if there is any file including the keyword in its name, then reuse it.
  while read path
  do
    remove_definition "$path" "$alias" "$response"
    exit $?
  done < <(find "$responses_dir" -type f -name "*${keyword}*")

  # if there is any file including the keyword in its keyword definitions, then reuse it.
  while read path
  do
    remove_definition "$path" "$alias" "$response"
    exit $?
  done < <(egrep -r "^#\s*${keyword}\s*$" "$responses_dir" | cut -d ':' -f 1)

  exit 1
}

remove_definition() {
  local path=$1
  local alias=$2
  local response=$3
  local modified=0

  log "Removing a response from $path..."

  if egrep "^#\s*${keyword}\s*$" "$path" > /dev/null
  then
    log "Removing keyword \"$keyword\"..."
    $esed -e "/^#[$whitespaces]*${keyword}[$whitespaces]*$/d" -i "$path"
    modified=1
  fi

  if [ "$alias" != '' ]
  then
    if egrep "^#\s*${alias}\s*$" "$path" > /dev/null
    then
      log "Removing alias \"$alias\" for \"$keyword\"..."
      $esed -e "/^#[$whitespaces]*${alias}[$whitespaces]*$/d" -i "$path"
      modified=1
    fi
  fi

  if [ "$response" != '' ]
  then
    if egrep "^\s*${response}\s*$" "$path" > /dev/null
    then
      log "Removing response \"$response\"..."
      $esed -e "/^[$whitespaces]*${response}[$whitespaces]*$/d" -i "$path"
      modified=1
    fi
  fi

  if [ $? = 0 ]
  then
    if [ $modified = 0 ]
    then
      log 'Nothing to be removed.'
    else
      log 'Successfully removed.'
      "$tools_dir/generate_responder.sh"
    fi
    return 0
  else
    log 'Failed to remove.'
    return 1
  fi
}


case "$operation" in
  add ) process_add_command;;
  del*|rem* ) process_remove_command;;
esac
