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
alias gld='cd ~/.dotfiles && git pull && git submodule update'
