#!/bin/bash
# Dotfiles install script, hosted on https://smirnov.link/d
git clone https://github.com/issmirnov/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install
echo "If you would like to use zsh, please run ~/.dotfiles/zsh/setup"
