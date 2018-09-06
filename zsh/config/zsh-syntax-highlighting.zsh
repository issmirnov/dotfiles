# vim:ft=zsh
# Docs: https://github.com/zsh-users/zsh-syntax-highlighting/blob/master/docs/highlighters.md

# define proper variable types, otherwise they are reset in the plugin init code.
typeset -ga ZSH_HIGHLIGHT_HIGHLIGHTERS
export ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern)

# add rules for highlights
typeset -gA ZSH_HIGHLIGHT_PATTERNS
export ZSH_HIGHLIGHT_PATTERNS=('rm -rf *' 'fg=white,bold,bg=red')
# To add more patterns:
#ZSH_HIGHLIGHT_PATTERNS+=('other pattern' 'fg=green,bold,bg=white')
