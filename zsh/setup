#!/usr/bin/env bash

# setup script, called by dotbot

# check if zsh is even installed
hash zsh 2>/dev/null || { echo >&2 "I require zsh but it's not installed.  Install it."; exit 0;}

# change shell to zsh
if [ $(basename $SHELL) == "zsh" ]; then
    # already zsh
    echo 'shell already zsh, no changes needed'
else
    chsh -s "$(which zsh)"
fi
