#!/usr/bin/env zsh

# This is a simple plugin to run commands based on directories I am in.
# I recall seeing a project like this, but I can't find it anywhere
# This file was written with the help of ChatGPT, so any copyright issues
# are completely unintended. If you are the original author of this idea,
# please get in touch and I am delighted to credit you here.
# Thank you.


# Function that runs whenever the current directory is changed
function run_directory_specific() {
  # Check if the current directory has a .directory-specific file
  if [[ -f ".directory-specific" ]]; then
    # Source the .directory-specific file to run its commands
    echo "found directory-specific, do you want to execute?"
    # add security here to avoid silly hack
    source .directory-specific
  fi
}

# Hook the function to run whenever the directory is changed
autoload -U add-zsh-hook
add-zsh-hook chpwd run_directory_specific

# Run the function for the initial directory at shell startup
run_directory_specific
