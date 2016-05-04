#!/bin/zsh

cd ~/.dotfiles
git pull
git submodule update
rm -rf zsh-config
./install.sh
git status

