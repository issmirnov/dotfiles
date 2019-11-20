#!/usr/bin/env bash
set -ex
FILE=weather

#url=$1
url='wttr.in/?mQ0&format=%c%t&period=60'

command="curl --silent $url  > $FILE"

if [ ! -a "$FILE" ];then
    echo "file not found, running command"
    eval "${command}"
    exit 0
fi

mtime=$(stat -f "%m" $FILE)
now=$(date +'%s')
lifespan=10 # 600 # 10 minutes.

if (( $(echo "$now > ($mtime + $lifespan)" | bc) ));then
    echo "file is old, refreshing"
    ${!command}
fi
