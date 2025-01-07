#!/usr/bin/env bash

# This is a simple script to grab the currently running hyprland command
# Once the HYPRLAND_INSTANCE_SIGNATURE is found and exported, we can run commands to hyprctl
# like: `hyprctl dispatch dpms on`

 # Exit on error. Append "|| true" if you expect an error.
set -o errexit
# Exit on error inside any functions or subshells.
set -o errtrace
# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset
# Catch the error in case command1 fails (but command2 succeeds) in `command1 |command2`
set -o pipefail
# Turn on traces, useful while debugging but commented out by default
# set -o xtrace

# Get the PID of the Hyprland process
HYPRLAND_PID=$(ps aux | grep "/usr/lib/xdg-desktop-portal-hyprland" | grep -v "grep" | awk '{print $2}')

# Check if the PID was found
if [ -z "$HYPRLAND_PID" ]; then
    echo "Hyprland process not found."
    exit 1
fi

# Get the HYPRLAND_INSTANCE_SIGNATURE from the environment variables of the process
HYPRLAND_INSTANCE_SIGNATURE=$(cat /proc/$HYPRLAND_PID/environ | tr '\0' '\n' | grep HYPRLAND_INSTANCE_SIGNATURE | cut -d '=' -f2)

# Check if the signature was found
if [ -z "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
    echo "HYPRLAND_INSTANCE_SIGNATURE not found."
    exit 1
fi

# Export the variable
export HYPRLAND_INSTANCE_SIGNATURE
echo "${HYPRLAND_INSTANCE_SIGNATURE}"
