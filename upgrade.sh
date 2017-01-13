#!/bin/zsh
# deprecate vundle
mv vim/Vundle.vim vim/v
git submodule deinit vim/Vundle.vim
git rm vim/Vundle.vim
rm -rf .git/modules/vim/Vundle.vim
rm -rf vim/v

