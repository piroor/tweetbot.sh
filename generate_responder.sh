#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
tweet_sh="$tools_dir/tweet.sh/tweet.sh"

source "$tweet_sh"

if [ "$TWEET_BASE_DIR" != '' ]
then
  TWEET_BASE_DIR="$(cd "$TWEET_BASE_DIR" && pwd)"
else
  TWEET_BASE_DIR="$work_dir"
fi

responder="$TWEET_BASE_DIR/responder.sh"

echo 'Generating responder script...' 1>&2
echo "  sources: $TWEET_BASE_DIR/responses" 1>&2
echo "  output : $responder" 1>&2

cat << FIN > "$responder"
#!/usr/bin/env bash
#
# This file is generated by "generate_responder.sh".
# Do not modify this file manually.

base_dir="\$(cd "\$(dirname "\$0")" && pwd)"

input="\$(cat |
            # remove all whitespaces
            sed 's/[ \f\n\r\t　]+/ /g'
            # normalize waves
            sed 's/〜/～/g')"

choose_random_one() {
  local input="\$(cat)"
  local n_lines="\$(echo "\$input" | wc -l)"
  local index=\$(((\$RANDOM % \$n_lines) + 1))
  echo "\$input" | sed -n "\${index}p"
}

extract_response() {
  local source="\$1"
  local responses="\$(cat "\$source" |
                        grep -v '^#' |
                        grep -v '^\s*\$')"

  [ "\$responses" = '' ] && return 1

  echo "\$responses" | choose_random_one
}

FIN

cd "$TWEET_BASE_DIR"

if [ -d ./responses ]
then
  ls ./responses/* |
    sort |
    grep -v '^default\.txt$' |
    while read path
  do
    matcher="$(\
      # first, convert CR+LF => LF
      nkf -Lu "$path" |
        # extract comment lines as definitions of matching patterns
        grep '^#' |
        # remove comment marks
        sed -e 's/^#\s*//' \
            -e '/^\s*$/d' |
        # concate them to a list of patterns
        paste -s -d '|')"
    [ "$matcher" = '' ] && continue
    cat << FIN >> "$responder"
if echo "\$input" | egrep -i "$matcher" > /dev/null
then
  extract_response "\$base_dir/$path"
  exit \$?
fi

FIN
  done

  default_file='./responses/default.txt'
  if [ ! -f "$default_file" ]
  then
    default_file="$(ls ./responses/* |
                     sort |
                     tail -n 1)"
  fi
  if [ -f "$default_file" ]
  then
    cat << FIN >> "$responder"
# fallback to the last pattern
extract_response "\$base_dir/$default_file"
exit 0

FIN
  fi
fi

cat << FIN >> "$responder"
# finally fallback to an error
exit 1
FIN

chmod +x "$responder"