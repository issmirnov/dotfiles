#!/usr/bin/env zsh
# Core ZSH config params
#
# Report CPU usage for commands running longer than 130 seconds
# Info: https://nuclearsquid.com/writings/reporttime-in-zsh/
REPORTTIME=30

# Aliases in Zsh and Bash are normally only expanded for the first
# word in a command. This means that your aliases will not normally
# get expanded when running the sudo command. One way to make the
# next word expand is to make an alias for sudo ending with a space.
alias sudo='sudo '
