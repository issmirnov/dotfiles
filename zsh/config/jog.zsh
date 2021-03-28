#!/usr/bin/env zsh

# Source: https://github.com/natethinks/jog/

# Note: first run  will require touch ~/.zsh_history_ext
# We could check for file existence each time, but that would be slow
# Note: `zshaddhistory` is an official zsh hook:
# http://zsh.sourceforge.net/Doc/Release/Functions.html
function zshaddhistory() {
	echo "${1%%$'\n'}|${PWD}   " >> ~/.zsh_history_ext
}

function jog(){
    grep -a "${PWD}   " ~/.zsh_history_ext | cat | cut -f1 -d"|" | tail
}
