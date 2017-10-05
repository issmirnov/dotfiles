# Let aliases be sudo'ed
alias sudo="sudo "

# Detect which `ls` flavor is in use
if ls --color > /dev/null 2>&1; then
  colorflag="--color"
else
  colorflag="-G"
fi

# Copy output of last command to clipboard
alias cl="fc -e - | pbcopy"

# clear shortcuts
alias cds="cd && clear && ls"
alias cls="clear && ls"

# create and enter directory
function mdc() {
    mkdir -p $1
    cd $1
}
## some OS dependent aliases ##
if [[ $OSTYPE == 'linux-gnu' ]]; then
	alias update='sudo apt update'
	alias upgrade='sudo apt -y upgrade; sudo apt autoremove'
	alias ins='sudo apt install'
	alias rem='sudo apt remove'
	alias open='xdg-open'
    alias ll='ls -lha --color'
elif [[ $OSTYPE == darwin* ]]; then
	alias update='brew update'
    alias ins="osx_ins"
    alias ll='ls -lha'
    function upgrade() {
        # check for permissions
        if [[ "$(stat -f '%u' /usr/local)" != "$(id -u)" ]];then
            echo "/usr/local is not owned by $(whoami)"
            sudo chown -R `whoami`:admin /usr/local
        fi
        # run upgrades
        brew upgrade
        brew cleanup
    }
fi


alias ta='tmux attach -t '

alias space='du -sh * | sort -h'

# nvbn/thefuck for correcting stupid mistakes
alias fuck='eval $(thefuck $(fc -ln -1 | tail -n 1)); fc -R'

# fix ubuntu gpg error
alias fixgpg='sudo apt-key adv --recv-keys --keyserver keyserver.ubuntu.com'

# tar commands
alias tarx='tar xvzf'
alias tarc='tar cvzf'

# triggering urgent bell
alias urgent='echo -e "'"\a"'"'

# i3 aliases
alias i3c='vim ~/.i3/config'

# find files fast
unalias ff
function ff () {
    find . -iname "*$@*" ;
}
