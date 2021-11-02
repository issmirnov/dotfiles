## Define all paths here. This simplifies hunting for random path clobbering.
# vim:ft=zsh

DOT_BIN="$HOME/.dotfiles/bin"
USER_BIN="$HOME/bin"
SYSTEM="/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
PYTHON="$HOME/.local/bin:$HOME/Library/Python/3.9/bin" # pip install target for linux and macos

# OS-dependent  paths.
if [[ $OSTYPE == 'linux-gnu' ]]; then
  TEX="/usr/texbin"
elif [[ $OSTYPE == darwin* ]]; then
  TEX="/usr/local/texlive/2014/bin/universal-darwin"
fi

# additional autocompletions
fpath=($HOME/.dotfiles/zsh/config/fpath /opt/homebrew/share/zsh/site-functions /usr/local/share/zsh/site-functions /usr/share/zsh/vendor-completions $fpath)

# Go Definitions
export GOPATH=$HOME/go
GOLANG_BIN="/usr/local/go/bin:/usr/lib/go/bin"

# Ubuntu Snaps are installed to /snap/bin symlinks
SNAP_BIN="/snap/bin"


# Homebrew 3.0
BREW="/opt/homebrew/bin"
# Check for symlinks to directories in bin and
# append them to the path. This is useful when linking in
# a suite such as flutter or android SDK.
local elem
for elem in $USER_BIN/*; do
    if [[ -L "$elem" && -d "$elem" ]]
    then
        USER_BIN=$USER_BIN:$elem
    fi
done
unset elem

# export final result
export PATH="$USER_BIN:$DOT_BIN:$GOPATH/bin:$BREW:$SNAP_BIN:$PYTHON:$TEX:$GOPATH/bin:$GOLANG_BIN:$FZF_PREFIX/fzf/bin:$SYSTEM"
