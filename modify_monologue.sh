#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
source "$tools_dir/common.sh"

input="$(cat |
           # normalize waves
           sed -E 's/〜/～/g')"
# +target(>(alias))?( +(body))?
# -target(>(alias))?( +(body))?

log 'Modifying monologue definitions...'

operation="$(echo "$input" | sed -E "s/^([-+]).*$/\1/")"
target="$(echo "$input" | sed -E "s/^[-+]([^${whitespaces}>&]+).*$/\1/")"
alias=''
if echo "$input" |
     egrep "^[^>&]+(>|&gt;)[$whitespaces]*${non_whitespaces}+" > /dev/null
then
  alias="$(echo "$input" |
    sed -E -e "s/^[^>&]+(>|&gt;)[$whitespaces]*//" \
          -e "s/(${non_whitespaces}+).*$/\1/")"
fi
body="$(echo "$input" |
  sed -E -e "s/^[-+]+[^${whitespaces}>&]+[$whitespaces]*((>|&gt;)[$whitespaces]*${non_whitespaces}+)?[$whitespaces]*//" |
  $tweet_sh resolve-all)"

log "  operation: $operation"
log "  target   : $target"
log "  alias    : $alias"
log "  body     : $body"

if [ "$target" = '' ]
then
  log "ERROR: No target is given."
  exit 1
fi


process_add_command() {
  local safe_target="$(echo "$target" |
                         # remove dangerous characters
                         sed -E -e "s/[!\[\]<>\{\}\/\\:;?*'\"|]+/_/g")"

  local exact_path="$monologues_dir/$target.txt"
  if [ -f "$exact_path" ]
  then
    add_definition "$exact_path" "$alias" "$body"
    exit $?
  fi

  # if there is any file including the target in its aliases, then reuse it.
  while read path
  do
    add_definition "$path" "$alias" "$body"
    exit $?
  done < <(egrep -r "^#[$whitespaces]*($target|$alias)[$whitespaces]*$" "$monologues_dir" | cut -d ':' -f 1)
  #NOTE: This must be done with a process substitution instead of
  #      simple pipeline, because we need to execute the loop in
  #      the same process, not a sub process.
  #      ("exit" in a sub-process loop produced by "egrep | cut | while read..."
  #       cannot exit actually.)

  # otherwise, create new definition file.
  local path="$monologues_dir/all-${safe_target}.txt"
  echo "# $target" > "$path"
  add_definition "$path" "$alias" "$body"
  exit $?
}

add_definition() {
  local path=$1
  local alias=$2
  local body=$3
  local modified=0

  log "Adding new body to $path..."

  # always insert new line, otherwise the added line can be
  # connected to the last existing line!
  echo "" >> "$path"

  if [ "$alias" != '' ]
  then
    if egrep "^#[$whitespaces]*${alias}[$whitespaces]*$" "$path" > /dev/null
    then
      : # found
    else
      log "Adding new alias \"$alias\" for \"$target\"..."
      echo "# $alias" >> "$path"
      modified=1
    fi
  fi

  if [ "$body" != '' ]
  then
    if egrep "^[$whitespaces]*${body}[$whitespaces]*$" "$path" > /dev/null
    then
      : # found
    else
      log "Adding new body \"$body\"..."
      echo "$body" >> "$path"
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
      if [ "$body" != '' ]
      then
        local index=$(cat "$path" | egrep -v "^#|^[$whitespaces]*$" | \
                      grep -x -n "$body" | cut -d ':' -f 1)
        log "New body is added at $index."
      fi
      "$tools_dir/generate_monologue_selector.sh"
    fi
    return 0
  else
    log 'Failed to add.'
    return 1
  fi
}


process_remove_command() {
  local exact_path="$monologues_dir/$target.txt"
  if [ -f "$exact_path" ]
  then
    remove_definition "$path" "$alias" "$body"
    exit $?
  fi

  # if there is any file including the target in its target definitions, then reuse it.
  while read path
  do
    remove_definition "$path" "$alias" "$body"
    exit $?
  done < <(egrep -r "^#[$whitespaces]*($target|$alias)[$whitespaces]*$" "$monologues_dir" | cut -d ':' -f 1)
  #NOTE: This must be done with a process substitution instead of
  #      simple pipeline, because we need to execute the loop in
  #      the same process, not a sub process.
  #      ("exit" in a sub-process loop produced by "egrep | cut | while read..."
  #       cannot exit actually.)

  exit 1
}

remove_definition() {
  local path=$1
  local alias=$2
  local body=$3
  local modified=0

  log "Removing a body from $path..."

  if [ "$alias" != '' ]
  then
    if egrep "^#\s*${alias}\s*$" "$path" > /dev/null
    then
      log "Removing alias \"$alias\" for \"$target\"..."
      sed -E -e "/^#[$whitespaces]*${alias}[$whitespaces]*$/d" -i "$path"
      modified=1
    fi
  fi

  if [ "$body" != '' ]
  then
    if egrep "^\s*${body}\s*$" "$path" > /dev/null
    then
      log "Removing body \"$body\"..."
      sed -E -e "/^[$whitespaces]*${body}[$whitespaces]*$/d" -i "$path"
      modified=1
    else
      # specified by an index
      if echo "$body" | egrep '^[0-9]+$' > /dev/null
      then
        log "Removing body at $body..."
        local line=$(cat "$path" | egrep -v "^#|^[$whitespaces]*$" | \
                     sed -n -e "${body}p")
        log " => \"$line\""
        sed -E -e "/^${line}$/d" -i "$path"
        modified=1
      fi
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
      "$tools_dir/generate_monologue_selector.sh"
      if [ "$(egrep -v "^#|^[$whitespaces]*$" "$path" | wc -l)" = 0 ]
      then
        log 'There is no more body.'
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

  # first, put aliases.
  grep '^#' "$path" |
    sort > "${path}_sorted"

  # separator line between aliases and bodies
  echo '' >> "${path}_sorted"

  # output bodies
  grep -v '^#' "$path" |
    grep -v "^[$whitespaces]*$" |
    # normalize wave
    sed 's/〜/～/g' |
    sort >> "${path}_sorted"

  mv "${path}_sorted" "$path"
}

case "$operation" in
  + ) process_add_command;;
  - ) process_remove_command;;
esac
