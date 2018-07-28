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

# vagrant
alias vup='vagrant up'
