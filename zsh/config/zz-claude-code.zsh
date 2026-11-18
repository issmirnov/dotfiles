# Shell options for Claude Code's Bash tool. Claude Code sets CLAUDECODE=1 in
# the shells it starts, so a terminal you open yourself keeps the defaults.
#
# nomatch off: an unmatched glob, such as a ? in a URL, reaches the command as
# typed instead of failing with "no matches found".
# aliases off: commands run as written. The interactive aliases (rm, cp and mv
# with -i, fd as a find call, one- and two-letter shortcuts) made agent calls
# prompt, misbehave, or fail when a script defined a function with an alias's
# name.
#
# noclobber (opts.zsh) stays on, so an agent can't overwrite a file with >.
# The zz- prefix loads this file after every other file in config/.
if [[ -n $CLAUDECODE ]]; then
  unsetopt nomatch aliases
fi
