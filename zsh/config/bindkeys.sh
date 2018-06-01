# Inspiration: https://sgeb.io/posts/2014/04/zsh-zle-custom-widgets/
# Resources:
#  - http://zsh.sourceforge.net/Doc/Release/Zsh-Line-Editor.html#Zle-Builtins
# Notes:
#  - `bindkey -M vicmd` will show all bound commands



# remove all escape binds, to speed up shell
# bindkey -rpM viins '^['
# bindkey -rpM vicmd '^['

# remove default binds that I don't like
bindkey -r "gUU"



# Make Vi mode transitions faster (KEYTIMEOUT is in hundredths of a second)
export KEYTIMEOUT=1

# fzf

# chains fzf cd widget to vi insert mode
function _fzf-cd-insert {
	zle fzf-cd-widget
	zle vi-insert
}
zle -N _fzf-cd-insert

bindkey -M vicmd '/' fzf-history-widget
bindkey -M vicmd -r '\-'
bindkey -M vicmd '\-' _fzf-cd-insert
bindkey -M vicmd -r "s"
bindkey -M vicmd 's' push-line-or-edit

# edit command line
autoload -U edit-command-line
zle -N edit-command-line
bindkey -M vicmd -r "S"
bindkey -M vicmd 'S' edit-command-line


# expand history refs like !!
bindkey -M viins ' ' magic-space
# doesn't quite work yet
# bindkey -M vicmd -s 'z' 'zsh-reload^M'

# line navigation
bindkey -M vicmd -r 'k'
bindkey -M vicmd 'k' vi-end-of-line
bindkey -M vicmd -r 'j'
bindkey -M vicmd 'j' vi-beginning-of-line


bindkey -M viins '^K' autosuggest-accept

alias zlasearch='zle -la G '
alias vilist='bindkey -M vicmd'



# Updates editor information when the keymap changes.
function zle-keymap-select() {
  zle reset-prompt
  declare VIM=${vi_info}
  zle -R
}

zle -N zle-keymap-select

function vi_mode_prompt_info() {
  echo "${${KEYMAP/vicmd/[% NORMAL]%}/(main|viins)/[% INSERT]%}"
}


function vi_info(){
	echo "${${KEYMAP/vicmd/⌘}/(main|viins)/$}"
}


# define right prompt, regardless of whether the theme defined it
RPS1='$(vi_mode_prompt_info)'
RPS2=$RPS1
