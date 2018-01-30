#!/bin/zsh
# Handy ubuntu aliases
if [[ $OSTYPE == 'linux-gnu' ]]; then

# sound
alias maxvol='amixer -D pulse sset Master '"'"'100%='"'"''
alias minvol='amixer -D pulse sset Master '"'"'0%='"'"''

# launch free file sync with root rights
alias ffs='gksudo FreeFileSync'

# mount server
alias mp='sudo mount -t cifs //puma/data /mnt/puma-data -o username=vania,file_mode=0777,dir_mode=0777'

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
    vared -p 'Name your screenshot: ' -c sn
    echo "Select screen area..."
    maim --noopengl  -s ~/Pictures/$sn.png
    echo "Done! Saved to ~/Pictures/$sn.png"
}
fi
