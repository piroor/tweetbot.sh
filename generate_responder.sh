#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
source "$tools_dir/common.sh"

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

# do nothing with the probability 1/N
probable() {
  local probability=\$1
  [ "\$probability" = '' ] && probability=2

  if [ \$((\$RANDOM % \$probability)) -eq 0 ]
  then
    return 0
  fi

  cat
}

extract_response() {
  local source="\$1"
  if [ ! -f "\$source" ]
  then
    echo ""
    return 0
  fi

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
    egrep -v '/_|^_' |
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
  [ "\$DEBUG" != '' ] && echo "Matched to \"$matcher\", from \"\$base_dir/$path\"" 1>&2
  extract_response "\$base_dir/$path"
  exit \$?
fi

FIN
  done

  pong_file='./responses/_pong.txt'
  connectors_file='./responses/_connectors.txt'
  questions_file='./responses/_questions.txt'
  following_questions_file='./responses/_following-questions.txt'
  default_file='./responses/_default.txt'
  cat << FIN >> "$responder"
# fallback to generated-patterns
[ "\$DEBUG" != '' ] && echo "Not matched to any case" 1>&2
[ "\$NO_QUESTION" != '' ] && exit 1

# Use "default" responses only if it is the first mention
# (not a reply of existing context)
if [ -f "\$base_dir/$default_file" \
     -a "\$IS_REPLY" != '1' \
     -a "\$(echo 1 | probable $OBSESSION_TO_SELF_TOPICS)" = '' ]
then
  extract_response "\$base_dir/$default_file"
else
  if [ "\$IS_REPLY" = '1' ]
  then
    # If it is a reply of continuous context, you can two choices:
    if [ "\$(echo 1 | probable $FREQUENCY_OF_CAPRICES)" != '' ]
    then
      # 1) Change the topic.
      #    Then we should reply twite: a "pong" and "question about next topic".
      pong="\$(extract_response "\$base_dir/$pong_file")"

      question="\$(extract_response "\$base_dir/$questions_file" | probable $ENDLESSNESS)"
      if [ "\$question" != '' ]
      then
        # "pong" can be omitted if there is question
        pong="\$(echo "\$pong" | probable 9)"
        [ "\$pong" != '' ] && pong="\$pong "

        connctor="\$(extract_response "\$base_dir/$connectors_file" | probable 9)"
        [ "\$connector" != '' ] && connctor="\$connctor "
        question="\$connctor\$question"
      fi
    else
      # 2) Continue to talk about the current topic.
      #    The continueous question should be a part of "pong".
      pong="\$(extract_response "\$base_dir/$pong_file" | probable 10)"
      following="\$(extract_response "\$base_dir/$following_questions_file" | probable $CONVERSATION_SPAN)"
      [ "\$following" != '' ] && pong="\$pong \$following"
    fi
  else
    # If it is not a reply, we always start new conversation without "pong".
    question="\$(extract_response "\$base_dir/$questions_file")"
  fi

  # Then output each responses.
  [ "\$pong" != '' ] && echo "\$pong"
  [ "\$question" != '' ] && echo "\$question"
fi

exit 0

FIN
fi

chmod +x "$responder"
