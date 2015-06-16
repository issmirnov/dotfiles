#!/bin/bash
#
# Script to initialize home directory.
# Author: Vania S. Based strongly on https://github.com/cowboy/dotfiles


# update git submodules
git submodule init
git submodule update
cd zsh-config
git checkout master
cd ..


DOTFILES_ROOT="`pwd`"


# Script to initialize home directory.

# check if zsh is even installed
hash zsh 2>/dev/null || { echo >&2 "I require zsh but it's not installed.  Install it."; sudo apt-get install zsh; }

# change shell to zsh
chsh -s /bin/zsh


# helper function
link_files () {
  ln -s $1 $2
  echo "linked $1 to $2"
}


# might not be needed if zsh-config properly set
#link_files $DOTFILES_ROOT/oh-my-zsh ~/.oh-my-zsh


# nuke old zhrc symlink, only good for updates
rm ~/.zshrc

# main function
install_dotfiles () {
  # iterate through all symlink files.
  for source in `find $DOTFILES_ROOT -maxdepth 2 -name \*.symlink`
  do
    dest="$HOME/.`basename \"${source%.*}\"`" # generate name without symlink suffix

    if [ -f $dest ] || [ -d $dest ] # if exists, delete file
    then
      rm -rf $dest
      echo "removed $dest"
    fi

    # link files
    link_files $source $dest
  done

  # manual i3 installation
  mkdir ~/.i3
  ln -s ~/.dotfiles/i3/ubuntu/config ~/.i3/config # default to ubuntu
  ln -s ~/.dotfiles/i3/i3status-laptop/.i3status.conf ~/.i3status.conf

  # Manual terminator installation
  mkdir -p ~/.config/terminator
  ln -s ~/.dotfiles/config-terminator/config ~/.config/terminator/config

  # Manual amix/vimrc link
  ln -s ~/.dotfiles/vimrc ~/.vim_runtime
  sh ~/.vim_runtime/install_awesome_vimrc.sh
}


# actual work
install_dotfiles

echo 'Done.'
