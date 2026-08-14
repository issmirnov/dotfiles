## Define all paths here. This simplifies hunting for random path clobbering.
# vim:ft=zsh

DOT_BIN="$HOME/.dotfiles/bin"
USER_BIN="$HOME/bin"
SYSTEM="/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
PYTHON="$HOME/.local/bin:$HOME/Library/Python/3.9/bin" # pip install target for linux and macos

# OS-dependent  paths.
# JAVA_BIN lists 21 before 17 so `java` resolves to 21 (matches JAVA_HOME in env.zsh).
if [[ $OSTYPE == 'linux-gnu' ]]; then
  TEX="/usr/texbin"
  JAVA_BIN="/usr/lib/jvm/java-21-openjdk/bin:/usr/lib/jvm/java-17-openjdk/bin"
elif [[ $OSTYPE == darwin* ]]; then
  TEX="/usr/local/texlive/2014/bin/universal-darwin"
  JAVA_BIN="/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/opt/openjdk@17/bin"
fi

# additional autocompletions
fpath=($HOME/.dotfiles/zsh/config/fpath /opt/homebrew/share/zsh/site-functions /usr/local/share/zsh/site-functions /usr/share/zsh/vendor-completions $fpath)

# Go Definitions
export GOPATH=$HOME/go
GOLANG_BIN="$HOME/.local/go/bin:/usr/local/go/bin:/usr/lib/go/bin"
RUST_BIN="$HOME/.cargo/bin"

# Ubuntu Snaps are installed to /snap/bin symlinks
SNAP_BIN="/snap/bin"

# npm global
# set up with "mkdir -p ~/.npm-global" && "npm config set prefix '~/.npm-global'"
NPM_PATH="$HOME/.npm-global/bin"

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
# ${VAR:+$VAR:} appends only when VAR is set, so an unmatched $OSTYPE (JAVA_BIN/TEX
# unset) can't leave an empty PATH element — which would put CWD ahead of trusted dirs.
export PATH="${JAVA_BIN:+$JAVA_BIN:}$USER_BIN:$DOT_BIN:$GOPATH/bin:$NPM_PATH:$BREW:$SNAP_BIN:$PYTHON:${TEX:+$TEX:}$GOPATH/bin:$GOLANG_BIN:$RUST_BIN:$FZF_PREFIX/fzf/bin:$SYSTEM"
