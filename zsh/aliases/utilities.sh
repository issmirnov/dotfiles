# Fix potentially broken commands
command -v md5sum > /dev/null || alias md5sum="md5"

# Interactive write to file.
function to {
	if [[ -z "$1" ]]; then
		echo "Usage: to <file name>"
	else
		echo "Now writing out to $1. Type ^D to finish.\n"
		cat >| $1
	fi
}

# gurl ~ Compressed curl
alias gurl="curl --compressed"

# week ~ Get week number
alias week="date +%V"

#emptytrash ~ Empty the trash on all mounts and clear system logs
alias emptytrash="sudo rm -rfv /Volumes/*/.Trashes; sudo rm -rfv ~/.Trash; sudo rm -rfv /private/var/log/asl/*.asl"

# map ~ Kickass map function
alias map="xargs -n1"

alias zsh-reload="source ~/.zshrc"
alias gld='cd ~/.dotfiles && git pull && git submodule update --init --recursive && popd'
alias c='cheat'

# Search through text of PDF's. Requires poppler.
function pdfsearch() {
    [ -z "$1" ] && echo "Error: No search term supplied" && exit 1
    find . -name '*.pdf' | xargs -I {} sh -c "pdftotext \"{}\" - | grep --with-filename --label=\"{}\" --color $1"
}


# wrapper around find
unalias f
function f(){
    find . -iname "*$1*"
}
