# zsh config

This folder is used to define various config options.
Of special interest is the file `paths.sh`. This serves as the
universal source of truth for `$PATH`, and minizes confusion.

Note that the files are loaded in alphabetical order. There is
one known dependency right now: fzf must be loaded before PATH,
since we set the binary prefix location.

If you find yourself needing to run `zsh` twice to get your aliases
working as expected, this is probably the cause. Check the order that
the files load in.
