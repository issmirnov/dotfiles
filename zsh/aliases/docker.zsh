#!/usr/bin/env zsh

alias dit='docker run -it '
# quick debug containers
alias alpine='docker run -ti alpine'
alias ubuntu='docker run -ti ubuntu:jammy sh'
alias dutil='docker run -ti issmirnov/util'
alias docker-top='docker run --rm -it --name=ctop --volume /var/run/docker.sock:/var/run/docker.sock:ro quay.io/vektorlab/ctop:latest'

# docker compose
alias dcup='docker compose up -d'
alias dcupf='dcup --force-recreate'
alias dcd='docker compose down'
alias dcfl='docker compose logs --follow'

# aliad docker-compose to "docker compose", as `docker-compose` is present and ancient on some systems
alias docker-compose='docker compose'
