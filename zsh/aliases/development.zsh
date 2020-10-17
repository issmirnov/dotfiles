# vim:ft=zsh
## python
alias pi='python3 -i'
alias pserver="python -m SimpleHTTPServer"

## ansible
alias ap='ansible-playbook'
alias agi='ansible-galaxy install -r requirements.yml --ignore-errors --keep-scm-meta'
alias agif='agi --force'
# get ansible facts
af() {
  ansible localhost -m setup | sed 's@localhost | SUCCESS => {@{@g' | jq ".ansible_facts.$1"
}
# profile playbook
alias pap='ANSIBLE_CALLBACK_WHITELIST="profile_roles, profile_tasks, timer" ap'

# vagrant
alias vup='vagrant up'

# docker
alias ubuntu='docker run -ti ubuntu:bionic sh'

# terraform
alias tf=terraform
