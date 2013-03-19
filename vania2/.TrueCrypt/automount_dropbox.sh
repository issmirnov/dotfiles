#!/bin/sh
truecrypt --mount /media/Data/dropbox.tc /media/truecrypt1
sleep 4

dbox_dir=/media/truecrypt1/Dropbox
while true
do
  if [ -d "$dbox_dir" ]
  then
    echo Dropbox folder is ready
    break
  else
    echo Dropbox folder not available
  fi
  sleep 2
done

echo DO DROPBOX STUFF HERE
dropbox start -i
