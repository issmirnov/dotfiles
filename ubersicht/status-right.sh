#!/bin/bash

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


~/.dotfiles/ubersicht/lib/Weather/curl.sh
WEATHER=$(cat ~/.dotfiles/ubersicht/lib/Weather/forecast)

WIFI_SSID=$(networksetup -getairportnetwork en0 | cut -c 24-)
WIFI_DISABLED=$(networksetup -getairportnetwork en0 | grep -cE "All Wi-Fi network services are disabled.")

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
