######################
## basic zsh config ##

# Save each command's timestamp and duration.
setopt EXTENDED_HISTORY

# Incrementally append history instead of waiting for exit to write out.
setopt INC_APPEND_HISTORY

# Ignore duplicate commands.
setopt HIST_IGNORE_ALL_DUPS

# Ignore commands that start with a space.
setopt HIST_IGNORE_SPACE

# Reduce blanks in history.
setopt HIST_REDUCE_BLANKS

# Allow for history expansion.
setopt HIST_VERIFY

# Don't clobber files accidentally.
setopt NOCLOBBER

# Uncomment following line if you want red dots to be displayed while waiting for completion
#COMPLETION_WAITING_DOTS="true"

# Uncomment following line if you want to  shown in the command execution time stamp
# in the history command output. The optional three formats: "mm/dd/yyyy"|"dd.mm.yyyy"|
# yyyy-mm-dd
HIST_STAMPS="yyyy-mm-dd"


######################
## oh-my-zsh config ##
export ZSH=$HOME/.dotfiles/oh-my-zsh

ZSH_THEME="ys" # theme for oh-my-zsh. Currently loading ys from $OMZ/custom/themes

plugins=(git git-extras zsh-completions alias-tips history brew brew-cask common-aliases osx tmux taskwarrior fasd extract adb)

source $ZSH/oh-my-zsh.sh # note that this comes AFTER plugins sourced.

source ~/.dotfiles/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
