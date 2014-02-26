alias reload!='. ~/.zshrc'

## standard aliases ##
alias update='sudo apt-get update'
alias ins='sudo apt-get install'
alias rem='sudo apt-get remove'
alias ls='ls --color'
alias ll='ls -lha --color'


## favorite aliases for python
alias pt='python3 -m doctest'
alias pv='python3 -m doctest -v'
alias p='python3'
alias pi='python3 -i'


alias lcsX='ssh -X cs61c-ic@bcom11.eecs.berkeley.edu'
alias lcs='ssh -X cs61c-ic@bcom11.eecs.berkeley.edu'

# clones all git branches
function cloneall {
for branch in `git branch -a | grep remotes | grep -v HEAD | grep -v master `; do
   git branch --track ${branch#remotes/origin/} $branch
done
}
alias compile='gcc --std=c99 -o '
