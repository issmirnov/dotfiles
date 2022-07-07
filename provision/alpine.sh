#!/usr/bin/env bash

 # Exit on error. Append "|| true" if you expect an error.
set -o errexit
# Exit on error inside any functions or subshells.
set -o errtrace
# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset
# Catch the error in case command1 fails (but command2 succeeds) in `command1 |command2`
set -o pipefail
# Turn on traces, useful while debugging but commented out by default
# set -o xtrace

echo "installing core dependencies"
apk add bash python3 build-base git zsh bat build-base fzf the_silver_searcher findutils-locate coreutils util-linux vim tmux

echo "Installing dotfiles"
wget smirnov.link/d -O- | bash

touch ~/.zsh_history_ext
echo "setting zsh to default shell and loading interactive session"
zsh -c "~/.dotfiles/zsh/setup; zsh -i"
