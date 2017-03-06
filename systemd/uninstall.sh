#!/usr/bin/env bash

names="$(cd /etc/systemd/system &&
           find -type f -name "*_tweetbot.service" |
           cut -d '/' -f 2 |
           sed 's/_tweetbot.service$//')"

if [ "$(echo "$names" | wc -l)" = "0" ]
then
  echo "Nothing to be uninstalled."
  exit
fi

echo "$names" | nl
read -p "Input the number of the bot to be uninstalled(1): " uninstall_index
[ "$uninstall_index" = '' ] && uninstall_index=1

uninstall_name="$(echo "$names" | sed -n "${uninstall_index}p")"

[ "$uninstall_name" = '' ] && exit

read -p "Are you sure to uninstall the bot \"$uninstall_name\"?(y/N): " confirmation
if echo "$confirmation" | egrep -i '^y' >/dev/null 2>&1
then
  systemctl stop "${uninstall_name}_tweetbot"
  systemctl disable "${uninstall_name}_tweetbot"
  rm "/etc/systemd/system/${uninstall_name}_tweetbot.service"
  echo 'Done.'
fi

