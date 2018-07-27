# Utilities and Configs that help with copy pasting text

# Fixes issue with incredibly slow paste.
# https://github.com/zsh-users/zsh-syntax-highlighting/issues/295#issuecomment-214549841
# https://github.com/zsh-users/zsh-autosuggestions/issues/141
# Can also do: ZSH_HIGHLIGHT_MAXLENGTH=300
zstyle ':bracketed-paste-magic' active-widgets '.self-*'


# Better URL paste magic. Quotes URL's that are pasted in, rather than escaping.
# https://github.com/zsh-users/zsh/blob/master/Functions/Zle/bracketed-paste-url-magic
autoload -Uz bracketed-paste-url-magic
zle -N bracketed-paste bracketed-paste-url-magic
