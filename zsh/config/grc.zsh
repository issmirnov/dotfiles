# Grc plugin
# Uses config from ~/.dotfiles/grc
# vim:ft=zsh
_grc_injector(){
    if (( ! ${+DISABLE_GRC} )); then
	for f in $(ls ~/.dotfiles/grc/conf*); do
	    local prog=${f:e}
	    if [[ "$BUFFER" =~ "(^|[/\w\.]+/)$prog\s?" && ! "$BUFFER" =~ "grcat conf*" ]]; then
		BUFFER=$BUFFER" | grcat conf.$prog"
		break
	    fi
	done
    fi
    zle .accept-line
}
zle -N accept-line  _grc_injector
