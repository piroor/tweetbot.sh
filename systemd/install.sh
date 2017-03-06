#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")/.." && pwd)"

name=''
data_dir="$work_dir"
tweetbot_dir="$tools_dir"
owner="$USER"

while getopts n:d:t:o:q OPT
do
  case $OPT in
    n )
      name="$OPTARG"
      ;;
    d )
      data_dir="$OPTARG"
      ;;
    t )
      tweetbot_dir="$OPTARG"
      ;;
    o )
      owner="$OPTARG"
      ;;
    q )
      quiet="true"
      ;;
  esac
done

validate() {
  [ "$name" != '' ] &&
    [ -d "$data_dir" ] &&
    [ -d "$tweetbot_dir" ] &&
    id "$owner" >/dev/null 2>&1
}

ask() {
  while true
  do
    if [ "$name" = '' ]
    then
      read -p "name of the bot: " tmp_name
    else
      read -p "name of the bot ($name): " tmp_name
    fi
    [ "$tmp_name" != '' ] && name="$tmp_name"
    [ "$name" != '' ] && break
  done

  while true
  do
    read -p "path to the data directory ($data_dir): " tmp_data_dir
    [ "$tmp_data_dir" != '' ] && data_dir="$tmp_data_dir"
    [ -d "$data_dir" ] && break
  done

  while true
  do
    read -p "path to the tweetbot.sh directory ($tweetbot_dir): " tmp_tweetbot_dir
    [ "$tmp_tweetbot_dir" != '' ] && tweetbot_dir="$tmp_tweetbot_dir"
    [ -d "$tweetbot_dir" ] && break
  done

  while true
  do
    read -p "run as ($owner): " tmp_owner
    [ "$tmp_owner" != '' ] && owner="$tmp_owner"
    id "$owner" >/dev/null 2>&1 && break
  done
}

confirm() {
  echo '----------------------------------------------------------------'
  echo "name           : $name"
  echo "data directory : $data_dir"
  echo "tweetbot.sh    : $tweetbot_dir"
  echo "run as         : $owner"
  echo '----------------------------------------------------------------'
  read -p 'OK?(y/N): ' confirmation
  echo "$confirmation" | egrep -i '^y' >/dev/null 2>&1
}

if [ "$quiet" = 'true' ]
then
  validate || exit
else
  while true
  do
    ask
    confirm && break
  done
fi

safe_name="$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's|[ :/\.]|_|g')"
pid_file="$data_dir/.pidfile"
dist_path="/etc/systemd/system/${safe_name}_tweetbot.service"
service_script_path="$data_dir/${safe_name}_tweetbot_service.sh"

echo "Generatiing service runner script to $service_script_path..."
echo '----------------------------------------------------------------'
cat "$tools_dir/systemd/service.sh" |
  sed -e "s|\${TWEETBOT_DIR}|$tweetbot_dir|g" \
      -e "s|\${DATA_DIR}|$data_dir|g" \
      -e "s|\${PID_FILE}|$pid_file|g" |
  tee "$service_script_path"
echo '----------------------------------------------------------------'
chmod +x "$service_script_path"
chown "$(stat -c "%U:%G" "$data_dir")" "$service_script_path"

echo "Installing new unit ${safe_name}_tweetbot..."
echo '----------------------------------------------------------------'
cat "$tools_dir/systemd/tweetbot.service" |
  sed -e "s|\${NAME}|$name|g" \
      -e "s|\${SERVICE_SCRIPT}|$service_script_path|g" \
      -e "s|\${PID_FILE}|$pid_file|g" \
      -e "s|\${OWNER}|$owner|g" |
  tee $dist_path
echo '----------------------------------------------------------------'

if [ -f "$dist_path" ]
then
  systemctl daemon-reload
  systemctl enable ${safe_name}_tweetbot
  echo 'Done.'
  echo 'Please start the service manually via:'
  echo "  systemctl start ${safe_name}_tweetbot"
else
  echo 'Failed to install.'
fi
