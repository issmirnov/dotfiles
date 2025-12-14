# Grc plugin
# Uses config from ~/.dotfiles/grc
# vim:ft=zsh

# Cache config files for performance
typeset -gA _GRC_COMMANDS
typeset -gA _GRC_TRANSFORMS

# Transform patterns for special cases
_GRC_TRANSFORMS=(
    'docker*' 'docker ${prog#docker}'
)

_grc_load_commands() {
    _GRC_COMMANDS=()
    for f in ~/.dotfiles/grc/conf.*; do
        [[ -f "$f" ]] || continue
        local prog=${f##*.}
        _GRC_COMMANDS[$prog]=$prog
    done
}

# Load commands once at startup
_grc_load_commands

_grc_injector(){
    if (( ! ${+DISABLE_GRC} )); then
        for prog in ${(k)_GRC_COMMANDS}; do
            local progmatch=$prog

            # Apply any transform patterns
            for pattern in ${(k)_GRC_TRANSFORMS}; do
                if [[ $prog == ${~pattern} ]]; then
                    # Evaluate the transform (e.g., 'docker ${prog#docker}')
                    eval "progmatch=\"${_GRC_TRANSFORMS[$pattern]}\""
                    break
                fi
            done

            # Match command execution contexts only (not arguments):
            # - Start of line: ps aux
            # - After path: /usr/bin/ps aux
            # - After sudo: sudo ps aux
            # - After pipe: cat file | ps
            # - After command separator: echo foo; ps
            if [[ "$BUFFER" =~ "(^|[/[:alnum:]._]+/|sudo[[:space:]]+|\|[[:space:]]*|;[[:space:]]*|&&[[:space:]]*|\|\|[[:space:]]*)($progmatch)([[:space:]]|$)" && \
                  ! "$BUFFER" =~ "grcat" ]]; then
                # Remove trailing newlines using parameter expansion (no subprocess!)
                BUFFER="${BUFFER%$'\n'} | grcat conf.$prog"
                break
            fi
        done
    fi
    zle .accept-line
}

zle -N accept-line _grc_injector
