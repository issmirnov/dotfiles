#!/bin/bash
#
# Script to initialize home directory.
# Author: Vania S. Based strongly on https://github.com/cowboy/dotfiles

DOTFILES_ROOT="`pwd`"


# Script to initialize home directory.

# check if zsh is even installed
hash zsh 2>/dev/null || { echo >&2 "I require zsh but it's not installed.  Install it."; sudo apt-get install zsh; }

# change shell to zsh
#chsh -s /bin/zsh







# helper function
link_files () {
  ln -s $1 $2
  echo "linked $1 to $2"
}

# link in oh-my-zsh - note, folder usually doesn't exist, so mv command fails
f=~/.oh-my-zsh
if test -h "$f"
then
    echo "$f is a symlink, all is well"
elif test -d "$f"
then
    mv $f $f.backup
else 
    echo "$f DNE"
    #mv $f $f.backup
    link_files $DOTFILES_ROOT/oh-my-zsh ~/.oh-my-zsh
fi


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
}

## Add binaries into the path, avodiding duplicates
new_entry="~/.dotfiles/bin"
echo $PATH | grep $new_entry
if [ $? = 1 ]
then
    PATH=$new_entry:$PATH
    export PATH 
    echo "adding path"
fi


# actual work
install_dotfiles

echo 'Done.'
