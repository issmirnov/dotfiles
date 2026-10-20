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
        # Same quoting, but with our own reader; see bracketed-paste-patient below.
        if zmodload zsh/system zsh/zselect 2>/dev/null; then
            zle -N bracketed-paste bracketed-paste-patient
        else
            zle -N bracketed-paste bracketed-paste-url-magic
        fi
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

# Read a bracketed paste up to its end marker ourselves. zsh's own reader
# (.bracketed-paste) ends the paste after $KEYTIMEOUT of silence, and
# bindkeys.zsh sets that to 10ms so ESC is instant. Terminals often pause
# longer mid-paste (foot sends \e[200~ before the source app has sent the
# text), and the rest then arrives as keystrokes: newlines run lines, and the
# closing \e[201~ becomes ESC (vicmd) + `~` (swaps the case of the last char).
# ZLE only reads KEYTIMEOUT when a prompt starts, so it can't be raised for
# just the paste. Quotes URLs the same way bracketed-paste-url-magic does.
function bracketed-paste-patient() {
    local end=$'\e[201~' buf= chunk before tty
    exec {tty}</dev/tty || { bracketed-paste-url-magic; return }
    {
        # Wait for the end marker however long it takes: giving up early would
        # run the rest of the paste as keystrokes. zselect retries on signals.
        while :; do
            if ! zselect -t 100 -r $tty; then
                # 1s without input: say why the line is stuck, then block.
                # With no timeout, status 1 can only be an error.
                zle -R "Waiting for the rest of the paste (^C cancels)"
                zselect -r $tty || break
            fi
            sysread -i $tty -s 8192 chunk || break  # EOF: tty went away
            buf+=$chunk
            # Only the newest bytes (plus some overlap) can complete the marker;
            # matching the whole buffer every time is quadratic on big pastes.
            [[ ${buf[-$(( $#chunk + 8 )),-1]} == *"$end"* ]] && break
        done
    } always {
        exec {tty}<&-  # also on ^C mid-paste
    }
    before=${buf%%"$end"*}
    # keys typed right behind the paste can land in the same read: replay them
    (( $#buf > $#before + $#end )) && zle -U -- "${buf:$(( $#before + $#end ))}"
    local content=${before//$'\r'/$'\n'}
    local -a schema
    zstyle -a :bracketed-paste-url-magic schema schema ||
        schema=(http:// https:// ftp:// ftps:// file:// ssh:// sftp:// magnet:)
    local wantquote=${NUMERIC:-0}
    (( wantquote == 0 )) && [[ $content = (${(~j:|:)schema})* ]] && wantquote=1
    (( wantquote == 1 )) && content=${(q-)content}
    local start=$#LBUFFER
    LBUFFER+=$content
    YANK_START=$start YANK_END=$#LBUFFER
    zle -f yank
}
