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

    # get OS name and add some hyper os specific aliases
    # mostly related to package management
    OSNAME=$(grep '^ID=' /etc/os-release | cut -d'=' -f 2 | tr -d '"')
    if [[ $OSNAME == ubuntu || $OSNAME == debian ]]; then
        # update: refresh package lists, then preview what's upgradable (read-only).
        alias update='sudo apt update && apt list --upgradable 2>/dev/null'
        # upgrade: refresh first (plain `apt upgrade` does not), then upgrade + autoremove.
        # `upgrade` never removes a package to satisfy another, so anything needing new or
        # removed deps stays "kept back" -- run `sudo apt full-upgrade` by hand for those.
        alias upgrade='sudo apt update && sudo apt -y upgrade && sudo apt -y autoremove'
        alias ins='sudo apt install'
        alias rem='sudo apt remove'
    elif [[ $OSNAME == arch || $OSNAME == archarm ]]; then
        # update: safe, read-only preview of pending repo + AUR updates.
        # checkupdates uses a throwaway temp DB (never the real one), so unlike a
        # bare `yay -Sy` it can't leave the system in a partial-upgrade state.
        alias update='checkupdates 2>/dev/null; yay -Qua'
        # upgrade: full repo + AUR upgrade in one combined transaction (combinedupgrade
        # is on). --sudoloop keeps the sudo credential alive through long AUR builds so
        # the install step never re-prompts and times out on an unattended run.
        alias upgrade='yay -Syu --sudoloop'
        alias ins='sudo pacman -Syy && yay -S'
        alias rem='yay -R'
    elif [[ $OSNAME == alpine ]]; then
        # update: refresh the index, then list upgradable packages (read-only preview).
        alias update='apk update && apk list -u'
        # upgrade: -U refreshes the index first, so this is a self-contained full upgrade.
        alias upgrade='apk upgrade -U'
        alias ins='apk add'
        alias rem='apk del'
    elif [[ $OSNAME == centos || $OSNAME == amzn ]]; then
        # update: on yum/dnf `update` installs updates just like `upgrade`, so use
        # check-update instead -- a read-only list of what's available (safe preview).
        alias update='sudo yum check-update'
        # upgrade: the actual upgrade (also processes obsoletes).
        alias upgrade='sudo yum upgrade'
        alias ins='sudo yum install'
        alias rem='sudo yum erase'
    else
        echo "OS type not known: ${OSNAME}, system.zsh will not load some common aliases"
    fi

    # generic linux aliases
    alias open='xdg-open'
    alias ll='ls -lha --color'
    alias cpuhogs='ps -Ao pcpu,pmem,comm,comm,pid --sort=-pcpu | head -n 6'
    alias copy='xclip -sel clip'
    # alias paste='xclip -sel clip -o'

elif [[ $OSTYPE == darwin* ]]; then
    # update: refresh formulae, then preview outdated packages (read-only).
    alias update='brew update && brew outdated'
    alias ins="osx_ins"
    alias ll='ls -lha'
    # upgrade: refresh first, then upgrade + clean up. (Dropped the old `sudo chown` of the
    # brew prefix -- Homebrew discourages it, and the hardcoded /usr/local path was wrong on
    # Apple Silicon, so the check misfired and chowned the prefix on every run.)
    alias upgrade='brew update && brew upgrade && brew cleanup'
    alias cpuhogs='ps -Aro pcpu,pmem,comm,comm,pid  | head -n 6'
    alias copy='pbcopy'
    # alias paste='pbpaste'
fi

# Copy output of last command to clipboard
alias copylast="fc -e - | copy" # using copy alias defined above

alias ta='tmux attach -t '
alias tls='tmux ls '


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

# jump to obsidian
function o..(){
  cd ~/Data/obsidian
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
