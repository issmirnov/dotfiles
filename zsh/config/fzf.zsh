# vim:ft=zsh
# Setup fzf
# ---------

# Set install dir
if [[ $OSTYPE == linux-* ]]; then
  export FZF_PREFIX=/opt
elif [[ $OSTYPE == darwin* ]]; then
  export FZF_PREFIX=/opt/homebrew/opt
else
  # FZF not available
  return 0
fi

# use spectrum_ls to list all ansi colors
# https://github.com/junegunn/fzf/wiki/Color-schemes
export FZF_DEFAULT_OPTS='
  --exact
  --color fg:-1,bg:-1,hl:230,fg+:193,bg+:233,hl+:231
  --color info:150,prompt:110,spinner:150,pointer:167,marker:174
  --tiebreak=pathname,length
  --border=rounded
'

if command -v fd > /dev/null; then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
elif command -v ag > /dev/null; then
  export FZF_DEFAULT_COMMAND='(git ls-tree -r --name-only HEAD || ag --hidden --ignore .git -g "") 2> /dev/null'
else
  export FZF_DEFAULT_COMMAND='(git ls-tree -r --name-only HEAD || find . -path "*/\.*" -prune -o -type f -print -o -type l -print | sed s/^..//) 2> /dev/null'
  echo "[FZF Module]: 'ag' and 'fd'  not found, falling back to 'find' (no hidden files)"
fi

# Set FZF fzf-file-widget to use the same options
# Other available overrides:
# fzf-file-widget: FZF_CTRL_T_COMMAND, FZF_CTRL_T_OPTS
# fzf-cd-widget: FZF_ALT_C_COMMAND, FZF_ALT_C_OPTS
# fzf-history-widget: FZF_CTRL_R_OPTS
export FZF_CTRL_T_COMMAND=$FZF_DEFAULT_COMMAND

# prettier history view
# history | fzf --tac --wrap --bind 'ctrl-/:toggle-wrap' --wrap-sign $'\t↳ '
# export FZF_CTRL_R_OPTS="--tac --wrap --bind 'ctrl-/:toggle-wrap' --wrap-sign $'\t↳ '"


# Auto-completion
[[ $- == *i* ]] && source "$FZF_PREFIX/fzf/shell/completion.zsh" 2> /dev/null

# Load Key bindings. Try custom install path, alpine path, and arch path.
[[ -f "$FZF_PREFIX/fzf/shell/key-bindings.zsh" ]] && source "$FZF_PREFIX/fzf/shell/key-bindings.zsh"
[[ -f "/usr/local/opt/fzf/shell/key-bindings.zsh" ]] && source "/usr/local/opt/fzf/shell/key-bindings.zsh"
[[ -f  "/usr/share/fzf/key-bindings.zsh" ]] && source "/usr/share/fzf/key-bindings.zsh"
[[ -f  "/usr/share/fzf/completion.zsh" ]] && source "/usr/share/fzf/completion.zsh"


# on new fzf versions, load baked in completions
eval "$(fzf --zsh)" || true

# better zz from fasd
# TODO convert to Z
function zz() {
  local dir
  dir="$(fasd -Rdl "$*" | fzf --query="$*" -1 -0 --no-sort +m)" && cd "${dir}" || return 1
}

# does global file search, shows selected file in bat
function show() {
    local file
    file=$(locate / | fzf --query="$*" --select-1 --exit-0 --preview="bat --color=always --style=full {}")
    [ ! -n "$file" ] && echo "no results found" && return -1
    [ -f "$file" ] && bat "$file"
    [ -d "$file" ] && cd "$file"
}

# does local file search, from current directory, displays file in bat
function showl() {
    local file
    file=$(fzf --query="$*" --select-1 --exit-0 --preview="bat --color=always --style=full {}")
    [ ! -n "$file" ] && echo "no results found" && return -1
    [ -f "$file" ] && bat "$file"
    [ -d "$file" ] && cd "$file"
}

# global file search -> vim
function vf() {
  local file;
  file="$(locate / | fzf --query="$*" --select-1 --exit-0)";
  [ ! -n "$file" ] && echo "no results found" && return -1
  [ -f "$file" ] && vim "$file"
  [ -d "$file" ] && echo "Result is a directory, running cd" && cd "$file"
}

# Pick file to edit
function vfl() {
  local file
  file=$(fzf --exact --height 40% --reverse --query="$*"  --select-1 --exit-0)
  [ ! -n "$file" ] && echo "no results found" && return -1
  [ -f "$file" ] && vim "$file"
  [ -d "$file" ] && echo "Result is a directory, running cd" && cd "$file"
}

# Search through all files with ag, then open file at location
# Requires Vim to have https://github.com/wsdjeg/vim-fetch
function vaf(){
  if [ !  "$*" ]; then
    echo "Usage: $0 search_term"
    exit 1
  fi
  local file
  file=$(ag -U $* | fzf --select-1 | cut -d':' -f -2)
  [ -n "$file" ] && vim "$file"
}

# Common function for directory selection
_fzf_cd() {
  local fd_flags=("--type" "d" "--follow" "--strip-cwd-prefix")  # Base optimized flags
  local query=()

  for arg in "$@"; do
    if [[ "$arg" == "-hide" ]]; then
      fd_flags+=("--hidden" "--no-ignore")
    else
      query+=("$arg")
    fi
  done

  local preview_cmd
  if command -v exa > /dev/null; then
    preview_cmd='exa -al --icons --color=always --group-directories-first {} 2>/dev/null | head -50'
  else
    preview_cmd='ls -A --color=always {} 2>/dev/null | head -50'
  fi

  local dir
  dir=$(fd "${fd_flags[@]}" "${query[@]}" 2>/dev/null | fzf --no-multi \
    --preview "$preview_cmd" \
    --preview-window=right:50%:wrap \
    --height=60% --layout=reverse --border=rounded \
    --query="${query[*]}") && cd "$dir"
}

# Regular directory search (ignores hidden dirs)
fa() {
  _fzf_cd "$@"
}

# Include hidden directories (except for .git)
fah() {
  _fzf_cd -hide "$@"
}


# global:  cd into the directory of the selected file
# similar to 'zz', but this one does a full global file search
fl() {
  local file
  local dir

  # Use fd to search from root `/`, ensuring it finds everything
  file=$(fd . / --type f --follow --exclude /proc --exclude /sys --exclude /dev | \
    fzf +m --query="$*" --height=60% --layout=reverse --border=rounded)

  [[ -n "$file" ]] && dir=$(dirname "$file") && cd "$dir" && ls
}

# cd into the directory of the selected file
fll() {
  local file
  local dir
  file=$(fzf +m -q "$*") && dir=$(dirname "$file") && cd "$dir"
  ls
}


# Search env variables
fenv() {
  local query="$1"  # Capture optional search term
  local preview_cmd
  local out

  # Preview: Show the variable name at the top, then its value below
  preview_cmd='var=$(echo {} | cut -d= -f1); echo -e "\033[1;32m$var\033[0m"; echo "--------------------"; printenv "$var"'

  # Use fzf with optional query
  out=$(env | fzf --query="$query" --preview "$preview_cmd" --preview-window=right:60%:wrap \
    --height=60% --layout=reverse --border=rounded)

  # If a variable was selected, print it nicely
  if [[ -n "$out" ]]; then
    local var_name=$(echo "$out" | cut -d= -f1)
    local var_value=$(printenv "$var_name")

    echo -e "\n\033[1;32m$var_name\033[0m="
    echo "$var_value"
  fi
}


cd..(){
  local declare dirs=()
  get_parent_dirs() {
    if [[ -d "${1}" ]]; then dirs+=("$1"); else return; fi
    if [[ "${1}" == '/' ]]; then
      for _dir in "${dirs[@]}"; do echo $_dir; done
    else
      get_parent_dirs $(dirname "$1")
    fi
  }
  local DIR=$(get_parent_dirs $(realpath "${1:-$PWD}") | fzf-tmux --tac)
  cd "$DIR"
}

# search source code, then pipe files with 10 line buffer into fzf preview using bat.
# requirements:
# - fzf: https://github.com/junegunn/fzf
# - ag: https://github.com/ggreer/the_silver_searcher
# - bat: https://github.com/sharkdp/bat
# Notes:
#  - if you want to replace ag for rg feel free (https://blog.burntsushi.net/ripgrep/)
#  - Same goes for bat, although ccat and others are definitely worse
#  - the $ext extraction uses a ZSH specific text globber
s(){
  local margin=5 # number of lines above and below search result.
  local preview_cmd='search={};file=$(echo $search | cut -d':' -f 1 );'
  preview_cmd+="margin=$margin;" # Inject value into scope.
  preview_cmd+='line=$(echo $search | cut -d':' -f 2 );'
  preview_cmd+='tail -n +$(( $(( $line - $margin )) > 0 ? $(($line-$margin)) : 0)) $file | head -n $(($margin*2+1)) |'
  preview_cmd+='bat --paging=never --color=always --style=full --file-name $file --highlight-line $(($margin+1))'
  local full=$(ag "$*" \
    | fzf --select-1 --exit-0 --preview-window up:$(($margin*2+1)) --height=60%  --preview $preview_cmd)
  local file="$(echo $full | awk -F: '{print $1}')"
  local line="$(echo $full | awk -F: '{print $2}')"
  [ -n "$file" ] && vim "$file" +$line
}

# If you want other awesome navigation shortcuts, check out:
# https://github.com/agkozak/zsh-z
# It's one of my most used commands.
