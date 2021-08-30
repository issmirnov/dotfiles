# vim:ft=zsh
# Fix potentially broken commands
command -v md5sum > /dev/null || alias md5sum="md5"

alias o='open'
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
#alias map="xargs -n1"

alias zsh-reload="source ~/.zshrc"
alias gld='cd ~/.dotfiles && git pull && git submodule update --init --recursive && popd'
alias c='cheat'

# Search through text of PDF's. Requires poppler.
function pdfsearch() {
    [ -z "$1" ] && echo "Error: No search term supplied" && exit 1
    find . -name '*.pdf' | xargs -I {} sh -c "pdftotext \"{}\" - | grep --with-filename --label=\"{}\" --color $1"
}

# Alias search. https://sgeb.io/posts/2016/11/til-alias-search/
alias als='alias | grep -i --'

#### https://ebzzry.io/en/zsh-tips-4/ ###
# applies $1 to all subsequent args
# ex: map 'git clone' repo1 repo2 repo3
function map () {
  for i (${argv[2,-1]}) { ${(ps: :)${1}} $i }
}

# inverse map - apply commands to first arg
# ex: rmap . 'du -h' stat 'sudo lsof'
function rmap () {
  for i (${argv[2,-1]}) { ${(ps: :)${i}} $1 }
}

# show true filepath
function fp () {
  [ -z "$1" ] && echo "Error: no target specified"  && exit 1
  echo "${1:A}"
}

# parallel removal of large trees
function rm+ () {
  parallel --will-cite 'rm -rf {}' ::: $@
}

#### end zsh-tips ####


# highlight - helper that adds color decorators to text
# credit: https://github.com/kepkin/dev-shell-essentials/blob/master/highlight.sh
highlight() {
    if [ "$#" -lt 2 ]; then
        echo "Usage: $0 black|red|green|yellow|blue|magenta|cyan your text here"
        return 2
    fi
    SED_CMD=sed

    # sed on OSX is messed up.
    # https://unix.stackexchange.com/questions/13711/differences-between-sed-on-mac-osx-and-other-standard-sed
    if [[ $OSTYPE == darwin* ]];then
      if (! exists gsed); then
        echo "Missing gnu-sed on OSX, please install."
        exit 1
      else
	SED_CMD=gsed
      fi
    fi

    declare -A fg_color_map
    fg_color_map[black]=30
    fg_color_map[red]=31
    fg_color_map[green]=32
    fg_color_map[yellow]=33
    fg_color_map[blue]=34
    fg_color_map[magenta]=35
    fg_color_map[cyan]=36

    fg_c=$(echo -e "\e[1;${fg_color_map[$1]}m")
    c_rs=$'\e[0m'
    shift
    $SED_CMD -u s"/$*/$fg_c\0$c_rs/g"
}

alias vimrc='vim ~/.vimrc'

alias batp='bat --style=plain'

# if 'bat' exists on system, enhance cat.
if (exists bat);then
  alias cat='bat --style=plain --paging=never'
fi

# Easily view config files. Removes all comments and displays actual live settings
# Usage: "cat /file/with/hashtag/comments "
alias -g prp='| grep -v "#" | sed "/^$/d"'


# Wrapper for cp, will mkdir if target doesn't exist. Useful when copying deep paths.
function cpd(){
    src=$1
    dest=$2
    case "$dest" in
    */)
        ndir=$dest
        ;;
    *)
        ndir=$(dirname $dest);
        ;;
    esac
    # try to make directory
    mkdir -p $ndir
    cp $src $dest
}

alias -g Gv='| grep -v '
