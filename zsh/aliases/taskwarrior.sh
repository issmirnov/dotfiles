### Task Warrior Utils ###

# inbox
alias in='task add +in'
alias inbox='task in'

# tickle file
tickle () {
    deadline=$1
    shift
    in +tickle wait:$deadline $@
}
tmrw() {
    if [[ $OSTYPE == 'linux-gnu' ]]; then
        date +'%Y-%m-%d' -d "+1 day"
    elif [[ $OSTYPE == darwin* ]]; then
        date -v +1d +'%Y-%m-%d'
    fi
}
alias tick=tickle
alias think="tickle $(tmrw)"

# Read and Review
webpage_title (){ # requires html-xml-utils for 'hxselect' tool
    wget -qO- "$*" | hxselect -s '\n' -c  'title' 2>/dev/null
}
read_and_review (){
    link="$1"
    title=$(webpage_title $link)
    #echo $title
    descr="\"Read and review: $title\""
    id=$(task add +rnr +@online "$descr" | sed -n 's/Created task \(.*\)./\1/p')
    task "$id" annotate "$link"
}
alias rnr=read_and_review

# goals. Filters on proj:goals.cur_month
alias tg="t goals proj:goals.${$(date +'%b'):l}"

# all waiting or pending
alias tawp='t all +WAITING or +PENDING'
