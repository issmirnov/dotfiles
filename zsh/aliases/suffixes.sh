# ZSH supports "suffix aliases", which allow executing commands based on file names. Incredible.
# Simply enter a file name as a command and magic happens.
# http://zsh.sourceforge.net/Intro/intro_8.html
# vim:ft=zsh

# cleanup aliases from oh-my-zsh/common-aliases
unalias -s pdf
unalias -s djvu

alias -s css=$EDITOR
alias -s html=$EDITOR
alias -s js=$EDITOR
alias -s log="tail"
alias -s md="$EDITOR"
alias -s pdf="open"
alias -s py=$EDITOR
alias -s yml="$EDITOR"
alias -s yaml="$EDITOR"

# URL's
alias -s org=google-chrome
alias -s com=google-chrome
alias -s in=google-chrome
alias -s io=google-chrome
alias -s wiki=google-chrome
