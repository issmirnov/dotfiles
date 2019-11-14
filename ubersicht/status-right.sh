#!/bin/bash

# Check if date exists
if ! [ -x "$(command -v date)" ]; then
  echo "{\"error\":\"date binary not found\"}"
  exit 1
fi

# Check if pmset exists
if ! [ -x "$(command -v pmset)" ]; then
  echo "{\"error\":\"pmset binary not found\"}"
  exit 1
fi

# Check if egrep exists
if ! [ -x "$(command -v egrep)" ]; then
  echo "{\"error\":\"egrep binary not found\"}"
  exit 1
fi

# Check if cut exists
if ! [ -x "$(command -v cut)" ]; then
  echo "{\"error\":\"cut binary not found\"}"
  exit 1
fi

# Check if memory_pressure exists
if ! [ -x "$(command -v memory_pressure)" ]; then
  echo "{\"error\":\"memory_pressure binary not found\"}"
  exit 1
fi

# Check if sysctl exists
if ! [ -x "$(command -v sysctl)" ]; then
  echo "{\"error\":\"sysctl binary not found\"}"
  exit 1
fi

# Check if osascript exists
if ! [ -x "$(command -v osascript)" ]; then
  echo "{\"error\":\"osascript binary not found\"}"
  exit 1
fi

# Check if df exists
if ! [ -x "$(command -v df)" ]; then
  echo "{\"error\":\"df binary not found\"}"
  exit 1
fi

# Check if grep exists
if ! [ -x "$(command -v grep)" ]; then
  echo "{\"error\":\"grep binary not found\"}"
  exit 1
fi

# Check if awk exists
if ! [ -x "$(command -v awk)" ]; then
  echo "{\"error\":\"awk binary not found\"}"
  exit 1
fi

# Check if networksetup exists
if ! [ -x "$(command -v networksetup)" ]; then
  echo "{\"error\":\"networksetup binary not found\"}"
  exit 1
fi

export LC_TIME="en_US.UTF-8"
TIME=$(date +"%H:%M")
DATE=$(date +"%a %m/%d")


BATT_INSTALLED=$(system_profiler SPPowerDataType | grep -cE "Battery Installed: Yes")
BATTERY_PERCENTAGE=$(pmset -g batt | egrep '([0-9]+\%).*' -o --colour=auto | cut -f1 -d'%')
# patch battery on desktop
if [[ $BATTERY_PERCENTAGE -eq "" ]];then
  BATTERY_PERCENTAGE=100
fi

BATTERY_STATUS=$(pmset -g batt | grep "'.*'" | sed "s/'//g" | cut -c 18-19)

BATTERY_CHARGING=""
if [ "$BATTERY_STATUS" == "Ba" ]; then
  BATTERY_CHARGING="false"
elif [ "$BATTERY_STATUS" == "AC" ]; then
  BATTERY_CHARGING="true"
fi

LOAD_AVERAGE=$(sysctl -n vm.loadavg | awk '{print $2}')
NUM_CPU=$(sysctl hw.physicalcpu | grep -o -E '[0-9]+')
CPU_TOTAL=$(ps -axro pcpu | awk '{sum+=$1} END {print sum}')
CPU_USAGE=$(echo "$CPU_TOTAL / $NUM_CPU" | bc)

VOLUME=$(osascript -e 'output volume of (get volume settings)')
IS_MUTED=$(osascript -e 'output muted of (get volume settings)')

MEMORY_FREE=$(memory_pressure | grep "System-wide" | grep -o -E '[0-9]+')
# MEMORY_FREE=$(memory_pressure | grep "Pages free" | grep -o -E '[0-9]+')
# MEMORY_TOTAL=$(memory_pressure | grep system | awk -F" " '{print $5}' | grep -o -E '[0-9]+')

~/.dotfiles/ubersicht/lib/Weather/curl.sh
# WEATHER=$(curl --silent 'wttr.in/?mQ0&format=%c%t&period=60')
WEATHER=$(cat ~/.dotfiles/ubersicht/lib/Weather/forecast)

WIFI_SSID=$(networksetup -getairportnetwork en0 | cut -c 24-)
WIFI_DISABLED=$(networksetup -getairportnetwork en0 | grep -cE "All Wi-Fi network services are disabled.")
# TODO: set this to null on desktop

# TODO: use jq to build dynamic json, rather than hardcoding it in a heredoc.
echo $(cat <<-EOF
{
  "datetime": {
    "time": "$TIME",
    "date": "$DATE"
  },
  "battery": {
    "percentage": $BATTERY_PERCENTAGE,
    "charging": $BATTERY_CHARGING,
    "installed" : $BATT_INSTALLED
  },
  "cpu": {
    "loadAverage": "${CPU_USAGE}"
  },
  "volume": {
	  "volume": $VOLUME,
	  "muted": $IS_MUTED
  },
  "memory": {
	  "free": $MEMORY_FREE
  },
  "weather": {
	  "forecast": "$WEATHER"
  },
  "wifi": {
	  "ssid": "$WIFI_SSID",
	  "disabled" : $WIFI_DISABLED
  }
}
EOF
)
