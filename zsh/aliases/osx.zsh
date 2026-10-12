# vim:ft=zsh
# vim: set tabstop=4:softtabstop=4:shiftwidth=4:expandtab
if [[ $OSTYPE == darwin* ]]; then

alias fixbrew='sudo chown -R $(whoami):admin $(brew --prefix)/*'

# OSX install wrapper. `brew install` auto-detects formula vs cask, so one path
# covers both -- the old `brew cask` subcommand was removed from Homebrew.
function osx_ins() {
    if brew info "$1" >/dev/null 2>&1; then
        echo "Running: brew install $1"
        brew install "$1"
    else
        echo "Package $1 not found in brew."
    fi
}

alias dfh='df -H -l | awk -F" " '"'"'{ $6="";  $7=""; $8=""; $10=""; print}'"'"' | column -t | grcat conf.df'


# Browse chrome history with fzf
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

# upgrade casks
alias upgrade_casks='brew cask outdated | xargs brew cask reinstall'

# updatedb
alias updatedb='sudo /usr/libexec/locate.updatedb'

alias google-chrome="/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome"

# service management
alias sr='brew services restart'
function ss(){
  brew services list | grep $1 | highlight green started | highlight red stopped
}
fi

# unalias buf as we use buf.build
# unalias buf
