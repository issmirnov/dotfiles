#!/bin/bash
## invoke with `curl vania.com/fetch.sh | sh`

set -e # causes this to exit if any command exits with non-zero code

if command -v git > /dev/null; then
  git clone http://github.com/vaniaspeedy/dotfiles.git ~/.pEnv
#else
  #echo "git not available, falling back to scp"
  #scp -rP 484 nomcopter@nomcopter.com:/home/nomcopter/pEnv ~/.pEnv
fi

# check for zsh
hash zsh 2>/dev/null || { echo >&2 "I require zsh but it's not installed.  Install it!"; }


exec ~/.dotfiles/vania-install.sh





# change shell
chsh -s /bin/sh
