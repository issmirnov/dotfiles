# i3 config

This folder contains my modular config for the i3 window manager.

## Overview

There is a git [commit hook](../git/) that triggers the `genconf` script after
 any changes in this folder. The script moves the old `i3/config` file
 to `/tmp`, and then builds a new one. All machines share `snippets/base`, and then
 depending on the snippet names listed in `profiles/$HOSTNAME` more config will be added.

The profile file simply defines a list of snippets, such as `laptop`, `desktop`, and
other snippets as needed, and the script will then take the contents of the files
in `snippets/$snippet` and append them to the base config.

This allows you to have arbitrarily structured config across all of your
machines. If two machines share any config, odds are you can factor it out into
a snippet and have them both reference it.

This modular config makes it very easy to propagate updates to any number of
machines, since the commit hook is guaranteed to run on every pull.
