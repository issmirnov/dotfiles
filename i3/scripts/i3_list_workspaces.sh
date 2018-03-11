#!/bin/bash
# Note: can use jq: ".[].name" to get the same list of names. 
i3-msg -t get_workspaces | tr ',' '\n' | grep "name" | sed 's/"name":"\(.*\)"/\1/g' | sort -n

