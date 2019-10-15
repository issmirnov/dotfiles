#!/usr/bin/env zsh

# Type text into input field.
function key(){
  adb shell input text "$@"
}
