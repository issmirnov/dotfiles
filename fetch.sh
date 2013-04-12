#!/bin/bash
## invoke with `curl vaniaspeedy.site44.com/fetch.sh | sh`

set -e # causes this to exit if any command exits with non-zero code

if command -v git > /dev/null; then
  git clone http://github.com/vaniaspeedy/dotfiles.git ~/.dotfiles
else
  echo "git not available, falling back to wget"
  #scp -rP 484 smivan@ocf.berkeley.edu:~/dotfiles ~/.dotfiles
fi

# check for zsh
hash zsh 2>/dev/null || { echo >&2 "I require zsh but it's not installed.  Install it!"; }


exec ~/.dotfiles/vania-install.sh





# change shell
chsh -s /bin/sh
