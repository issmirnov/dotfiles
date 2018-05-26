# zsh

**WARNING: This config uses `bindkey -v` rather than the [emacs default](https://sgeb.io/posts/2014/04/zsh-zle-custom-widgets/).**

This is a modular zsh config framework, originally built by
 [Andrew Brinker](https://github.com/AndrewBrinker/zsh).

At the top level there is a simple `zshrc` that when loaded will find all of the
files ending in `.sh` and load them in. The directory structure is pretty self
explanatory - there's a folder for aliases, various config and some exports that
contain handy functions.

The `setup` script is called by the `install` script one level up. It checks that
zsh is installed, and that it is the default shell.
