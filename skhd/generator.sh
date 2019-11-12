#!/usr/bin/env bash

# Fail fast.
if [[ $OSTYPE != darwin* ]]; then
    echo "Non macos host detected, ignoring"
    exit 0
fi

# Prepare base config.
rm skhdrc
cat base > skhdrc

# list of systems that have SIP disabled
# I considered using the CLI to get this dynamically, but csrutil has
# no useful interfaces, and it was cleaner to just hardcode my 2 hosts
# https://linuxize.com/post/how-to-compare-strings-in-bash/
host="$(hostname -s)"
if [ "$host" = "carbon" ] || [ "$host" = "flume" ];then
    echo "Found whitelisted host with System Integrity Disabled, adding in SIP commands in skhdrc."
    cat sip >> skhdrc
fi

# Pick up new changes
skhd --reload
