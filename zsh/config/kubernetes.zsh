#!/usr/bin/env zsh

[[ $commands[kubectl] ]] && source <(kubectl completion zsh)

# use https://github.com/dty1er/kubecolor
command -v kubecolor >/dev/null 2>&1 && alias kubectl="kubecolor"
