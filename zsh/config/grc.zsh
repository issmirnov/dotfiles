# Grc plugin
# Uses config from ~/.dotfiles/grc
# vim:ft=zsh
_grc_injector(){
    if (( ! ${+DISABLE_GRC} )); then
        local f
	for f in $(ls ~/.dotfiles/grc/conf*); do
	    local prog=${f:e}
	    # regex: match oneof:
	    #  - start of line
	    #  - whitespace
	    #  - sudo
	    # then check for existence of program (determined by grc file suffix) and make sure we don't infintely append to zsh BUFFER
	    if [[ "$BUFFER" =~ "(^|[/\w\.]+/|sudo\s+)$prog(\s|$)\s?" && ! "$BUFFER" =~ "grcat conf*" ]]; then
		BUFFER=$BUFFER" | grcat conf.$prog"
		break
	    fi
	done
    fi
    zle .accept-line
}
zle -N accept-line  _grc_injector
