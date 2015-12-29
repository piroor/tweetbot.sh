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


input="$(cat |
           # normalize waves
           sed 's/〜/～/g')"
# +response filename-or-keyword(>(alias))?( +(response))?
# -response filename-or-keyword(>(alias))?( +(response))?

log 'Modifying keyword definitions...'

whitespaces=' \f\n\r\t　'
non_whitespaces='[^ \f\n\r\t　]'

operation="$(echo "$input" | $esed "s/^(${non_whitespaces}+)[$whitespaces].+$/\1/")"
keyword="$(echo "$input" |
  $esed -e "s/^${non_whitespaces}+[$whitespaces]+//" \
        -e "s/[$whitespaces]*((>|&gt;)${non_whitespaces}+)?([$whitespaces].*)?$//")"
alias=''
if echo "$input" |
     egrep "^${non_whitespaces}+[$whitespaces]+[^>&]+(>|&gt;)[$whitespaces]*${non_whitespaces}+" > /dev/null
then
  alias="$(echo "$input" |
    $esed -e "s/^${non_whitespaces}+[$whitespaces]+[^>&]+(>|&gt;)[$whitespaces]*//" \
          -e "s/(${non_whitespaces}+)[$whitespaces]*([$whitespaces].*)?$/\1/")"
fi
response="$(echo "$input" |
  $esed -e "s/^${non_whitespaces}+[$whitespaces]+[^>&$whitespaces]+([$whitespaces]*(>|&gt;)[$whitespaces]*${non_whitespaces}+)?[$whitespaces]*//")"

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
  local safe_keyword="$(echo "$keyword" |
                         # remove dangerous characters
                         $esed -e "s/[!\[\]<>\{\}\/\\:;?*'\"|]+/_/g")"

  # if there is any file including the keyword in its name, then reuse it.
  while read path
  do
    add_definition "$path" "$alias" "$response"
    exit $?
  done < <(find "$responses_dir" -type f \
                                 -name "*${keyword}*" \
                                 -or -name "*${safe_keyword}*")

  # if there is any file including the keyword in its keyword definitions, then reuse it.
  while read path
  do
    add_definition "$path" "$alias" "$response"
    exit $?
  done < <(egrep -r "^#[$whitespaces]*${keyword}[$whitespaces]*$" "$responses_dir" | cut -d ':' -f 1)

  # otherwise, create new definition file.
  local path="$responses_dir/autoadd_${safe_keyword}.txt"
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
    if egrep "^#[$whitespaces]*${alias}[$whitespaces]*$" "$path" > /dev/null
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
    if egrep "^[$whitespaces]*${response}[$whitespaces]*$" "$path" > /dev/null
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
      normalize_contents "$path"
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
  done < <(egrep -r "^#[$whitespaces]*${keyword}[$whitespaces]*$" "$responses_dir" | cut -d ':' -f 1)

  exit 1
}

remove_definition() {
  local path=$1
  local alias=$2
  local response=$3
  local modified=0

  log "Removing a response from $path..."

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
      normalize_contents "$path"
      "$tools_dir/generate_responder.sh"
      if egrep -v "^#|^[$whitespaces]*$" "$path" > /dev/null
      then
        log 'There is no more response message.'
        loc 'Note: this keyword works as a filter to ignore mentions.'
      fi
    fi
    return 0
  else
    log 'Failed to remove.'
    return 1
  fi
}


normalize_contents() {
  local path="$1"

  # first, put keyword patterns.
  grep '^#' "$path" |
    sort > "${path}_sorted"

  # separator line between keywords and responses
  echo '' >> "${path}_sorted"

  # output response patterns
  grep -v '^#' "$path" |
    grep -v '^ *$' |
    # normalize wave
    sed 's/〜/～/g' |
    sort >> "${path}_sorted"

  mv "${path}_sorted" "$path"
}

case "$operation" in
  +* ) process_add_command;;
  -* ) process_remove_command;;
esac
