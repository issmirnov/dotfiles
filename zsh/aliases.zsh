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


# alias for cs61a-ko login
alias lcsX='ssh -X cs61a-ko@star.cs.berkeley.edu'
alias lcs='ssh -X cs61a-ko@star.cs.berkeley.edu'
## copy hw

STAR='cs61a-ko@star.cs.berkeley.edu:~'

function copyhw {
FOLDER=`echo "$1" | cut -d'.' -f1`
scp $1 $STAR/class/hw/$FOLDER/
}

# clones all git branches
cloneall ()
{
for branch in `git branch -a | grep remotes | grep -v HEAD | grep -v master `; do
   git branch --track ${branch#remotes/origin/} $branch
done
}
