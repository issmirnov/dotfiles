# git config

This folder contains a standard gitconfig and gitignore that I use. I've also
included my hooks directory, since that's responsible for generating the i3 config.

Of special interest is the `post-checkout` hook. It defines a function that can
check if any modifications were made to files that match a pattern, and run an
arbitrary command. This is extremely useful for generating new config files or
launching the `install` or `upgrade.sh` scripts at the root.
