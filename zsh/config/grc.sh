# Grc plugin
# Uses config from ~/.dotfiles/grc
_grc_injector(){
    if (( ! ${+DISABLE_GRC} )); then
	for f in $(ls ~/.dotfiles/grc); do
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
