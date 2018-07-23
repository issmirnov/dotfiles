# pko <content> : copy <content> to the clipboard
pko() {
    echo "$*" | piknik -copy
}

# pcf <file> : copy the content of <file> to the clipboard
pcf() {
    piknik -copy < $1
}

# pc : read the content to copy to the clipboard from STDIN
alias pc='piknik -copy'

# pp : paste the clipboard content
alias pp='piknik -paste'

# pm : move the clipboard content
alias pm='piknik -move'

# pz: delete the clipboard content
alias pz='piknik -copy < /dev/null'

# pcd [<dir>] : send a whole directory to the clipboard, as a tar archive
pcd() {
    tar czpvf - ${1:-.} | piknik -copy
  }

# ppr : extract clipboard content sent using the pcr command
alias ppd='piknik -paste | tar xzhpvf -'
