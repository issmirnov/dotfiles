#!/usr/bin/env bash

# Fail fast.
if [[ $OSTYPE != darwin* ]]; then
    echo "Non macos host detected, ignoring"
    exit 0
fi

# set script dir location, since we get invoked from the git hook
ROOT="$HOME/.dotfiles/skhd"

# Prepare base config.
rm $ROOT/skhdrc 2> /dev/null
cat $ROOT/base > $ROOT/skhdrc.generated

# list of systems that have SIP disabled
# I considered using the CLI to get this dynamically, but csrutil has
# no useful interfaces, and it was cleaner to just hardcode my 2 hosts
# https://linuxize.com/post/how-to-compare-strings-in-bash/
host="$(hostname -s)"
if [ "$host" = "carbon" ] || [ "$host" = "jodium" ];then
    echo "Found whitelisted host with System Integrity Disabled, adding in SIP commands in skhdrc."
    cat $ROOT/sip >> $ROOT/skhdrc.generated
fi

# Pick up new changes. Macs without skhd, or with it stopped, keep only the
# generated file; that must not fail the dotbot install.
if command -v skhd >/dev/null 2>&1; then
    skhd --reload || echo "skhd is not running; it reads skhdrc at next start"
else
    echo "skhd not installed; skipping reload"
fi
