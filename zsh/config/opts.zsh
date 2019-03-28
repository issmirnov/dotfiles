######################
## basic zsh config ##

# EDITOR is vim.
export EDITOR=vim
# Save each command's timestamp and duration.
setopt EXTENDED_HISTORY

# Expand '=command' as path of command
# e.g.) '=ls' -> '/bin/ls'
setopt EQUALS

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

# Evaluate prompt each time it is shown. Allows embedding commands.
setopt PROMPT_SUBST

# Show command execution time stamp in history.
# The optional three formats: "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
HIST_STAMPS="yyyy-mm-dd"

# long date format in ls(1)
# https://www.gnu.org/software/coreutils/manual/html_node/Formatting-file-timestamps.html
export TIME_STYLE=long-iso
