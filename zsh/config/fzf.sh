# Setup fzf
# ---------
export FZF_DEFAULT_OPTS='--exact' # prefer exact matches


if command -v ag > /dev/null; then
  export FZF_DEFAULT_COMMAND='(git ls-tree -r --name-only HEAD || ag --hidden --ignore .git -g "") 2> /dev/null'
else
  export FZF_DEFAULT_COMMAND='(git ls-tree -r --name-only HEAD || find . -path "*/\.*" -prune -o -type f -print -o -type l -print | sed s/^..//) 2> /dev/null'
  echo "[FZF Module]: 'ag' not found, falling back to 'find' (no hidden files)"
fi

if [[ $OSTYPE == 'linux-gnu' ]]; then
  echo "please add ubuntu fzf config to fzf.sh"
elif [[ $OSTYPE == darwin* ]]; then
  if [[ ! "$PATH" == */usr/local/opt/fzf/bin* ]]; then
    export PATH="$PATH:/usr/local/opt/fzf/bin"
  fi
  # Auto-completion
  [[ $- == *i* ]] && source "/usr/local/opt/fzf/shell/completion.zsh" 2> /dev/null
  # Key bindings
  source "/usr/local/opt/fzf/shell/key-bindings.zsh"
fi # end OS selector


# better zz from fasd
unalias zz
function zz() {
  local dir
  dir="$(fasd -Rdl "$1" | fzf --query="$1" -1 -0 --no-sort +m)" && cd "${dir}" || return 1
}

# does global file search, do zz -> ccat
function show() {
    local file
    if [[ -f "$1" ]]; then
        ccat "$1"
    else
        file=$(fzf --query="$1"\
          --select-1 --exit-0)
        [ -n "$file" ] && ccat "$file"
    fi
}

# Pick file to edit
function fv() {
  local file
  file=$(fzf --exact --height 40% --reverse --query="$1"  --select-1 --exit-0)
  [ -n "$file" ] && vim "$file"
}
#alias fv='vim $(fzf --height 40% --reverse --query="$1")'
