#!/usr/bin/env bash

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

# This little script uses `jc` and `jq` to figure out which network interface LAN is on, and patch it to 9000 mtu
IFACE=$(ifconfig | jc --ifconfig | jq '.[] | select(.ipv4_addr == "10.3.33.1")' | jq -r '.name')

logger "Patching ${IFACE} mtu..."
/usr/bin/ip link set dev ${IFACE} mtu 9000
