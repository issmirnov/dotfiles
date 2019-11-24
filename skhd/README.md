# skhd config

https://github.com/koekeishiya/skhd

Used to drive my window manager on OSX, currently
[yabai](https://github.com/koekeishiya/yabai)

## Modularity

I need multiple flavors of the skhd config. Specifically, I override the
ctrl+arrow controls on mission control to have fast desktop swaps. This only
works on systems where yabai is installed with the scripting add-on, and no
SIP. On hosts with System Integrity disabled
(https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection) 
we can inject the additional config. See the `generator.sh` for details.
