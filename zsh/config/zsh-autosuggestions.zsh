# vim:ft=zsh
declare -a ZSH_AUTOSUGGEST_STRATEGY
export ZSH_AUTOSUGGEST_STRATEGY=(match_prev_cmd)

# async, for speed
export ZSH_AUTOSUGGEST_USE_ASYNC=1

# spectrum_ls from oh-my-zsh will list all codes
export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=010'

# stop autuosuggestions after 100 chars
export ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=100
