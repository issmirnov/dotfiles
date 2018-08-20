# Utilities and Configs that help with copy pasting text
# vim:ft=zsh

# Smart URLs: https://github.com/tai-allman/prezto/modules/environment/init.zsh
# This logic comes from an old version of zim. Essentially, bracketed-paste was
# added as a requirement of url-quote-magic in 5.1, but in 5.1.1 bracketed
# paste had a regression. Additionally, 5.2 added bracketed-paste-url-magic
# which is generally better than url-quote-magic so we load that when possible.
autoload -Uz is-at-least
if [[ ${ZSH_VERSION} != 5.1.1 ]]; then
    if is-at-least 5.2; then
        # Better URL paste magic. Quotes URL's that are pasted in, rather than escaping.
        # https://github.com/zsh-users/zsh/blob/master/Functions/Zle/bracketed-paste-url-magic
        autoload -Uz bracketed-paste-url-magic
        zle -N bracketed-paste bracketed-paste-url-magic
    else
        if is-at-least 5.1; then
            autoload -Uz bracketed-paste-magic
            # Fixes issue with incredibly slow paste.
            # https://github.com/zsh-users/zsh-syntax-highlighting/issues/295#issuecomment-214549841
            # https://github.com/zsh-users/zsh-autosuggestions/issues/141
            # Can also do: ZSH_HIGHLIGHT_MAXLENGTH=300
            zstyle ':bracketed-paste-magic' active-widgets '.self-*'
            zle -N bracketed-paste bracketed-paste-magic
        fi
    fi
    autoload -Uz url-quote-magic
    zle -N self-insert url-quote-magic
fi
