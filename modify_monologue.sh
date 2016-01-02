#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
source "$tools_dir/common.sh"

input="$(cat |
           # normalize waves
           $esed 's/〜/～/g')"
# +target(>(alias))?( +(body))?
# -target(>(alias))?( +(body))?

log 'Modifying monologue definitions...'

operation="$(echo "$input" | $esed "s/^([-+]).*$/\1/")"
target="$(echo "$input" | $esed "s/^[-+]([^${whitespaces}>&]+).*$/\1/")"
alias=''
if echo "$input" |
     egrep "^[^>&]+(>|&gt;)[$whitespaces]*${non_whitespaces}+" > /dev/null
then
  alias="$(echo "$input" |
    $esed -e "s/^[^>&]+(>|&gt;)[$whitespaces]*//" \
          -e "s/(${non_whitespaces}+).*$/\1/")"
fi
body="$(echo "$input" |
  $esed -e "s/^[-+]+[^${whitespaces}>&]+[$whitespaces]*((>|&gt;)[$whitespaces]*${non_whitespaces}+)?[$whitespaces]*//")"

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
                         $esed -e "s/[!\[\]<>\{\}\/\\:;?*'\"|]+/_/g")"

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
      $esed -e "/^#[$whitespaces]*${alias}[$whitespaces]*$/d" -i "$path"
      modified=1
    fi
  fi

  if [ "$body" != '' ]
  then
    if egrep "^\s*${body}\s*$" "$path" > /dev/null
    then
      log "Removing body \"$body\"..."
      $esed -e "/^[$whitespaces]*${body}[$whitespaces]*$/d" -i "$path"
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
      "$tools_dir/generate_monologue_selector.sh"
      if egrep -v "^#|^[$whitespaces]*$" "$path" > /dev/null
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
