# Grc plugin
# Uses config from ~/.dotfiles/grc
# vim:ft=zsh
_grc_injector(){
    if (( ! ${+DISABLE_GRC} )); then
	for f in ~/.dotfiles/grc/conf*; do
	    local prog=${f##*.}

	    # don't set this to local, so that we can update this inside the "if" block
	    # we explicitly unset at the end of the function to clean up the env.
	    progmatch=$prog

	    # echo "PROG: $prog"
	    # docker patch, so that "dockerpull" and "dockerimages" config files get picked up
	    if [[ $prog == docker* ]]; then
	      # Add a space after the "docker" prefix
	      # save to second variable, as we need to match on the command with the space
	      # but pass the non-spaced version to the GRC prog
	      progmatch="docker ${prog#docker}"
	    fi
	    # echo "PROG after transform $progmatch"
	    # regex: match oneof:
	    #  - start of line
	    #  - whitespace
	    #  - sudo
	    # then check for existence of program (determined by grc file suffix) and make sure we don't infintely append to zsh BUFFER
	    if [[ "$BUFFER" =~ "(^|[/\w\.]+/|sudo\s+)\b$progmatch\b(\s*|$)" && ! "$BUFFER" =~ "grcat conf*" ]]; then
		BUFFER=$(echo "$BUFFER" | sed ':a;N;$!ba;s/\n$//')" | grcat conf.$prog"
		break
	    fi
	    unset progmatch
	done
    fi
    zle .accept-line
}
zle -N accept-line  _grc_injector
