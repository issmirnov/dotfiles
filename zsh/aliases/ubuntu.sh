#!/usr/bin/env zsh
# vim:ft=zsh
# Handy ubuntu aliases
if [[ $OSTYPE == linux-* ]]; then

# sound
#alias maxvol='amixer -D pulse sset Master '"'"'100%='"'"''
#alias minvol='amixer -D pulse sset Master '"'"'0%='"'"''

# print stats about partitons, excluding tmpfs mounts
alias dfh='df -h -x tmpfs -x devtmpfs | column -t'

# clipboard manipulation
alias cpb='xclip -sel clip'
alias cpbo='xclip -sel clip -o'

# systemd shortcuts
alias ss='sudo systemctl status' # note: conflicts with /bin/ss
alias sr='sudo systemctl restart'

# screenshot helper
function shot(){
    if [[ ! -n $1 ]];then
        vared -p 'Name your screenshot: ' -c sn
    else
        sn=$1
    fi
    echo "Select screen area..."
    maim --noopengl  -s ~/Pictures/$sn.png
    echo "Done! Saved to ~/Pictures/$sn.png"
}
fi
