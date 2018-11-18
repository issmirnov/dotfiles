# vim:ft=zsh
#
# Inspiration: https://sgeb.io/posts/2014/04/zsh-zle-custom-widgets/
# Resources:
#  - http://zsh.sourceforge.net/Doc/Release/Zsh-Line-Editor.html#Zle-Builtins
#  - http://bolyai.cs.elte.hu/zsh-manual/zsh_14.html # list of ZLE functions
# Notes:
#  - `bindkey -M vicmd` will show all bound commands

# Add back emacs keys, useful on MBP keyboards where ESC is unreachable
bindkey "^A" vi-beginning-of-line
bindkey "^E" vi-end-of-line

# remove all escape binds, to speed up shell
# bindkey -rpM viins '^['
# bindkey -rpM vicmd '^['

# remove default binds that I don't like
bindkey -r "gUU"
bindkey -r "gg"
bindkey -M vicmd -r "G"

# Fix backpace issues. See https://github.com/denysdovhan/spaceship-prompt/issues/91
bindkey "^?" backward-delete-char
bindkey '^h' backward-delete-char

# Make Vi mode transitions faster (KEYTIMEOUT is in hundredths of a second)
export KEYTIMEOUT=1

# fzf
# chains fzf cd widget to vi insert mode
function _fzf-cd-insert {
	zle fzf-cd-widget
	zle vi-insert
}
zle -N _fzf-cd-insert

zle -N fzf-history-widget
bindkey -M vicmd '/' fzf-history-widget
bindkey -M vicmd -r '\-'
bindkey -M vicmd '\-' _fzf-cd-insert

# https://sgeb.io/posts/2016/11/til-bash-zsh-half-typed-commands/
function vi-push-line-or-edit(){
    builtin zle .push-line-or-edit
    builtin zle .vi-insert
}
zle -N vi-push-line-or-edit

bindkey -M vicmd -r "s"
bindkey -M vicmd 's' vi-push-line-or-edit

# Duplicates last word in command. Useful for copying files.
# Note: `zle -U " "` did not work, see https://superuser.com/questions/835986/zsh-custom-widget-not-working-as-i-think-it-should for why
function vi-copy-prev-shell-word(){
    BUFFER="$BUFFER " # add space
    zle .end-of-line # move cursor to end of line
    zle .copy-prev-shell-word # duplicate word
    zle .vi-insert # switch to insert mode
}
zle -N vi-copy-prev-shell-word
bindkey -M vicmd -r "f"
bindkey -M vicmd 'ff' vi-copy-prev-shell-word

# edit command line
autoload -U edit-command-line
zle -N edit-command-line
bindkey -M vicmd -r "E"
bindkey -M vicmd 'E' edit-command-line

# move cursor on history scroll to EOL
# use Ctrl+v and then arrow key to get the codes
function up-line-or-history() {
    zle .up-line-or-history
    zle .end-of-line
}
zle -N up-line-or-history
bindkey -M viins -r "^[[A"
bindkey -M viins "^[[A" up-line-or-history

function down-line-or-history() {
    zle .down-line-or-history
    zle .end-of-line
}
zle -N down-line-or-history
bindkey -M viins -r "^[[B"
bindkey -M viins "^[[B" down-line-or-history

# expand history refs like !!
bindkey -M viins ' ' magic-space
# doesn't quite work yet
# bindkey -M vicmd -s 'z' 'zsh-reload^M'

# better handling of ../
# credit: https://grml.org/zsh/zsh-lovers.html
rationalise-dot() { 
if [[ $LBUFFER = *.. ]]; then  # initial trigger on third dot (".." -> "../../")
    LBUFFER+=/../
elif [[ $LBUFFER = *../ ]]; then  # climb directories and append slash for tab completion
    LBUFFER+=../
else 
    LBUFFER+=. # we still need a regular dot sometimes
fi
} 
zle -N rationalise-dot 
bindkey -M viins '.' rationalise-dot


# command quote helper - append $() and places cursor inside parens.
function _quote_helper(){
    zle .end-of-line
    BUFFER="$BUFFER \$()"
    zle .end-of-line
    zle .vi-backward-char
    zle .vi-insert # switch to insert mode
}
zle -N _quote_helper
bindkey -M vicmd '\`' _quote_helper

# line navigation
bindkey -M vicmd -r 'k'
bindkey -M vicmd 'k' vi-end-of-line
bindkey -M vicmd -r 'j'
bindkey -M vicmd 'j' vi-beginning-of-line



alias zlasearch='zle -la G '
alias vilist='bindkey -M vicmd'

# autosuggestions
bindkey -M viins '^K' autosuggest-accept
bindkey -r "^G"
bindkey -M viins "^G" autosuggest-clear

