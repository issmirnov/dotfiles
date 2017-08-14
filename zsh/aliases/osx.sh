# vim: set tabstop=4:softtabstop=4:shiftwidth=4:expandtab
if [[ $OSTYPE == darwin* ]]; then

alias fixbrew='sudo chown -R `whoami`:admin /usr/local'

# OSX install wrapper
function osx_ins() {
    if brew cask ls --versions $1 >/dev/null 2>/dev/null; then
        echo "Running: brew cask install $1"        
        brew cask install $1
        return
    fi
    if brew ls --versions $1 >/dev/null 2>/dev/null; then
        echo "Running: brew install $1"
        brew install $1
        return
    fi
    echo "Package $1 not found in brew or cask."
}

alias dfh='df -H -l | awk -F" " '"'"'{ $6="";  $7=""; $8=""; $10=""; print}'"'"' | column -t'


# Browse history with fzf
ch() {
  local cols sep
  cols=$(( COLUMNS / 3 ))
  sep='{::}'

  \cp -r ~/Library/Application\ Support/Google/Chrome/Default/History /tmp/h

  sqlite3 -separator $sep /tmp/h \
    "select substr(title, 1, $cols), url
     from urls order by last_visit_time desc" |
  awk -F $sep '{printf "%-'$cols's  \x1b[36m%s\x1b[m\n", $1, $2}' |
  fzf --ansi --multi | sed 's#.*\(https*://\)#\1#' | xargs open
}

fi
