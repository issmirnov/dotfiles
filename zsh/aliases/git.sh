alias g="git"
alias glog="git log --graph --pretty=format:'%Cred%h%Creset %an: %s - %Creset %C(yellow)%d%Creset %Cgreen(%cr)%Creset' --abbrev-commit --date=relative"
alias gp='git push origin HEAD'
alias gd='git diff'
alias gc='git commit'
alias gca='git commit -a'
alias gco='git checkout'
alias gb='git branch'
alias gs='git status -sb' # upgrade your git if -sb breaks for you. it's fun.
alias grm="git status | grep deleted | awk '{print \$3}' | xargs git rm"
alias gacm='git add -A; git commit -m '

# Uses git's autocompletion for inner commands. Assumes an install of git's
# bash `git-completion` script at $completion
completion=/usr/local/etc/bash_completion.d/git-completion.bash

if test -f $completion
then
  source $completion
fi


git-branch-del-regex() {
	git for-each-ref --format="%(refname:short)" refs/heads/$1 | xargs git branch -D
}

cloneall() {
	for branch in `git branch -a | grep remotes | grep -v HEAD | grep -v master `; do
	   git branch --track ${branch#remotes/origin/} $branch
	done
}
