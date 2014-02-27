#!/bin/bash
# xrandr commands for laptop config


xrandr --auto --output VGA1 --mode 1280x1024 --left-of LVDS1 # set dell e177 resolution, and location (right|left)

xrandr --auto --output LVDS1 --mode 1600x900 # internal screen
