function prompt_char {
	if [ $UID -eq 0 ]; then echo "#"; else echo $; fi
}


## display return code (not really used by me)
#local return_code="%(?..%{$fg[red]%}%? ↵%{$reset_color%})"
# RPS1="${return_code}" # also works, but not with right prompt.

# variables for conveneince
local current_dir='%{$fg_bold[blue]%}%(!.%1~.%~)'
local user_host='%(!.%{$fg_bold[red]%}.%{$fg_bold[green]%}%n@)%m '
local time='%{$fg_bold[yellow]%}%T %w%{$reset_color%}' # time in the form of HH:MM DAY DD
local git_branch='$(git_prompt_info)'


# Prompts. Notice the double quotes rather than single.
PROMPT="${user_host}${current_dir} ${git_branch}%_$(prompt_char) %{$reset_color%}" 

RPROMPT="${time}"

ZSH_THEME_GIT_PROMPT_PREFIX="("
ZSH_THEME_GIT_PROMPT_SUFFIX=") "


