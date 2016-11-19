#!/bin/bash

# Installs the i3-wm suite

## i3
sudo apt-get install i3

### support utils
sudo apt-get install gnome-settings-daemon feh gnome-control-center

## i3blocks
git clone git://github.com/vivien/i3blocks
cd i3blocks
make clean all
sudo make install
cd ..



## rofi
sudo apt-get install -y libxinerama-dev libxft2 libpango1.0-dev libpangocairo-1.0-0 libcairo2-dev libglib2.0-dev libx11-dev libstartup-notification0-dev libxkbcommon-dev libxkbcommon-x11-dev libxcb1-dev libx11-xcb-dev libxcb-ewmh-dev libxcb-icccm4-dev libxcb-util0-dev libxcb-xinerama0-dev
wget https://github.com/DaveDavenport/rofi/releases/download/1.2.0/rofi-1.2.0.tar.gz -O rofi.tgz
tar xvzf rofi.tgz
cd rofi*
./configure
make
sudo make install

# TODO: add Workspace:i3_switch_workspace to binds. 

# Dependenices for the "hop" script, which has bindings in the xbindkeysrc file.
sudo apt-get install python-pip
sudo pip install i3-py


## TODO: Figure out a way to download my wallpaper.
