#!/usr/bin/env zsh
# vim:ft=zsh
# This file is the second component of the directory injection mechanism created in
# https://github.com/issmirnov/oh-my-zsh/commit/48f3b0e1a2f2f02764504ab3157f2e643077936c
# The functions get dynamically loaded into the prompt and allow transformations such as
# `/super/long/common/path/a/b/c` -> `(p)/a/b/c`


# Set up your shortcuts here
typeset -A shortcuts # declare KV map
shortcuts["$GOPATH/src/"]="(go)"
shortcuts["/System/Library/Extensions"]="(S/L/E)"


function dir_head(){
    for k in "${(@k)shortcuts}"; do
        # (Q) removes one level of quotes from a variable
        # https://linux.die.net/man/1/zshexpn
        if [[ $PWD == ${(Q)k}* ]]; then
            echo -n "$shortcuts[$k]"
            break
        fi
    done
}

function dir_tail(){
    for k in "${(@k)shortcuts}"; do
        # (Q) removes one level of quotes from a variable
        # https://linux.die.net/man/1/zshexpn
        if [[ $PWD == ${(Q)k}* ]]; then
            echo -n "/${PWD#${(Q)k}}"
            found=true
            break
        fi
    done

    # show full path by default
    if [[ ! "$found" ]]; then
        echo %~
    fi
}
