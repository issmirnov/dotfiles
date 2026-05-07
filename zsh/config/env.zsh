# vim:ft=zsh
# fixing curses apps
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export TERM=xterm-256color

# Core config
export EDITOR=vim
export VISUAL=vim # editor for crontab

# OS-dependent locations
if [[ $OSTYPE == 'linux-gnu' ]]; then
	ANSIBLE_ROLES_PATH='/etc/ansible'
elif [[ $OSTYPE == darwin* ]]; then
	ANSIBLE_ROLES_PATH='/usr/local/etc/ansible'
fi

# Customize github.com/djui/alias-tips
export ZSH_PLUGINS_ALIAS_TIPS_REVEAL=1
export ZSH_PLUGINS_ALIAS_TIPS_REVEAL_EXCLUDES="(_ ll vi)"

# XDG config location
export XDG_CONFIG_HOME="$HOME/.config"

# Correct XDG_SESSION_TYPE when logind reports wayland but we're actually on X11
# (happens when connecting via Chrome Remote Desktop into a wayland-tagged seat).
# Without this, Wayland-aware apps like Chrome try Wayland and crash on missing socket.
if [[ -n "$DISPLAY" && -z "$WAYLAND_DISPLAY" && "$XDG_SESSION_TYPE" == "wayland" ]]; then
	export XDG_SESSION_TYPE=x11
fi
