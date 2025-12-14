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
    # Use variable for portability; falls back to detecting script location
    # Script is at: .dotfiles/zsh/config/grc.zsh
    # :h:h:h removes: grc.zsh, config/, zsh/ → gives us .dotfiles
    local grc_conf_dir="${GRC_CONF_DIR:-${${(%):-%x}:A:h:h:h}/grc}"
    for f in ${grc_conf_dir}/conf.*; do
        [[ -f "$f" ]] || continue
        local prog=${f##*.}
        # SECURITY: Validate config filename contains only safe characters
        [[ $prog =~ ^[a-zA-Z0-9._-]+$ ]] || continue
        _GRC_COMMANDS[$prog]=$prog
    done
}

# Load commands once at startup
_grc_load_commands

_grc_injector(){
    if (( ! ${+DISABLE_GRC} )); then
        # Early exit if no commands loaded
        (( ${#_GRC_COMMANDS[@]} )) || { zle .accept-line; return }

        for prog in ${(k)_GRC_COMMANDS}; do
            local progmatch=$prog

            # Apply any transform patterns
            for pattern in ${(k)_GRC_TRANSFORMS}; do
                if [[ $prog == ${~pattern} ]]; then
                    # Evaluate the transform (e.g., 'docker ${prog#docker}')
                    # NOTE: This eval is safe because _GRC_TRANSFORMS is hardcoded above
                    # and cannot be modified by user input
                    eval "progmatch=\"${_GRC_TRANSFORMS[$pattern]}\""
                    break
                fi
            done

            # SECURITY: Escape regex metacharacters in progmatch
            # This prevents config files with special chars from breaking regex
            local progmatch_escaped=${progmatch//(#m)[.?+*\[\](){}^$|\\]/\\$MATCH}

            # Match command execution contexts only (not arguments):
            # - Start of line: ps aux
            # - After path: /usr/bin/ps aux
            # - After sudo: sudo ps aux
            # - After pipe: cat file | ps
            # - After command separator: echo foo; ps
            if [[ "$BUFFER" =~ "(^|[/[:alnum:]._]+/|sudo[[:space:]]+|\|[[:space:]]*|;[[:space:]]*|&&[[:space:]]*|\|\|[[:space:]]*)($progmatch_escaped)([[:space:]]|$)" && \
                  ! "$BUFFER" =~ "grcat" ]]; then
                # SECURITY: Quote config filename to prevent command injection
                # Even though we validate above, defense in depth
                BUFFER="${BUFFER%$'\n'} | grcat 'conf.$prog'"
                break
            fi
        done
    fi
    zle .accept-line
}

zle -N accept-line _grc_injector
