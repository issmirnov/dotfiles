# vim: set tabstop=4:softtabstop=4:shiftwidth=4:expandtab
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
