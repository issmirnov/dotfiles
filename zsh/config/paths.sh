## Define all paths here. This simplifies hunting for random path clobbering.

GOLANG_OSX="/usr/local/go/bin"
CUSTOM_HOME="$HOME/bin"
SYSTEM="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# OS-dependent LaTeX paths.
if [[ $OSTYPE == 'linux-gnu' ]]; then
	TEX="/usr/texbin"
elif [[ $OSTYPE == darwin* ]]; then
	TEX="/usr/local/texlive/2014/bin/universal-darwin"
fi

export PATH="$CUSTOM_HOME:$TEX:$GOLANG_OSX:$SYSTEM"
