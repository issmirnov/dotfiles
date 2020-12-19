#!/usr/bin/env zsh
# vim:ft=zsh

# Let aliases be sudo'ed
alias sudo="sudo "

# Detect which `ls` flavor is in use
if ls --color > /dev/null 2>&1; then
  colorflag="--color"
else
  colorflag="-G"
fi


# clear shortcuts
alias cds="cd && clear && ls"
alias cls="clear && ls"

# create and enter directory
function mdc() {
    mkdir -p $1
    cd $1
}
## some OS dependent aliases ##
if [[ $OSTYPE == linux-* ]]; then
    alias update='sudo apt update'
    alias upgrade='sudo apt -y upgrade; sudo apt autoremove'
    alias ins='sudo apt install'
    alias rem='sudo apt remove'
    alias open='xdg-open'
    alias ll='ls -lha --color'
    alias cpuhogs='ps -Ao pcpu,pmem,comm,comm,pid --sort=-pcpu | head -n 6'
    alias copy='xclip -sel clip'
    alias paste='xclip -sel clip -o'
elif [[ $OSTYPE == darwin* ]]; then
    alias update='brew update'
    alias ins="osx_ins"
    alias ll='ls -lha'
    function upgrade() {
        # check for permissions
        if [[ "$(stat -f '%u' /usr/local/Homebrew)" != "$(id -u)" || "$(stat -f '%u' /usr/local/bin)" != "$(id -u)"  ]];then
            echo "$(brew --prefix)/* is not owned by $(whoami)"
            sudo chown -R $(whoami):admin $(brew --prefix)/*
        fi
        # run upgrades
        brew upgrade
        brew cleanup
    }
    alias cpuhogs='ps -Aro pcpu,pmem,comm,comm,pid  | head -n 6'
    alias copy='pbcopy'
    alias paste='pbpaste'
fi

# Copy output of last command to clipboard
alias copylast="fc -e - | copy" # using copy alias defined above

alias ta='tmux attach -t '

alias space='du -sh * | sort -h'

# nvbn/thefuck for correcting stupid mistakes
alias fuck='eval $(thefuck $(fc -ln -1 | tail -n 1)); fc -R'

# fix ubuntu gpg error
alias fixgpg='sudo apt-key adv --recv-keys --keyserver keyserver.ubuntu.com'

# tar commands
compress(){
  tar cvzf $1.tgz $1
}
# note: "extract" is provided by oh-my-zsh/plugins/extract


# triggering urgent bell
alias urgent='echo -e "'"\a"'"'

# i3 aliases
alias i3c='vim ~/.i3/config'

# find files fast
unalias ff
# unalias fd
function ff () {
    find . -iname "*$@*" ;
}


# ram usage counter.
# Credit: https://github.com/nikitavoloboev/dotfiles/blob/master/zsh/functions/functions.zsh#L480
function ram() {
    local sum
    local items
    local app="$1"
    if [ -z "$app" ]; then
        echo "First argument - pattern to grep from processes"
    else
        sum=0
        for i in `ps aux | grep -i "$app" | grep -v "grep" | awk '{print $6}'`; do
            sum=$(($i + $sum))
        done
        sum=$(echo $sum | awk '{ split( "KB MB GB TB" , v ); s=1; while( $1>1024 ){ $1/=1024; s++ } printf("%0.2f %s", $1, v[s]) }')
        # sum=$(echo "scale=2; $sum / 1024.0" | bc)
        if [[ $sum != "0.00 KB" ]]; then
            echo "${fg[blue]}${app}${reset_color} uses ${fg[green]}${sum}s${reset_color} of RAM."
        else
            echo "There are no processes with pattern '${fg[blue]}${app}${reset_color}' are running."
        fi
    fi
}

# jump to dotfiles
function d..(){
  cd ~/.dotfiles
}

# jump to dotfiles/zsh
function dz..(){
  cd ~/.dotfiles/zsh
}

# edit SSH config
function essh(){
  vim ~/.ssh/config
}

# checks for existence of binary
# use in scripts like so: if (! exists "foo"); then echo "doesn't exist";fi
# https://www.topbug.net/blog/2016/10/11/speed-test-check-the-existence-of-a-command-in-bash-and-zsh/
function exists(){
  if [[ -z "$1" ]]; then
    echo "Usage: exists cmd_name"
    exit 1
  fi
  (( $+commands[$1] ))
  return $?
}
