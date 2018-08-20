# vim:ft=zsh
# fixing curses apps
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export TERM=xterm-256color

# Core config
export EDITOR=vim


# OS-dependent locations
if [[ $OSTYPE == 'linux-gnu' ]]; then
	ANSIBLE_ROLES_PATH='/etc/ansible'
elif [[ $OSTYPE == darwin* ]]; then
	ANSIBLE_ROLES_PATH='/usr/local/etc/ansible'
fi

# Customize github.com/djui/alias-tips
export ZSH_PLUGINS_ALIAS_TIPS_REVEAL=1
export ZSH_PLUGINS_ALIAS_TIPS_REVEAL_EXCLUDES="(_ ll vi)"
