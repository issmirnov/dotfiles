# vim:ft=zsh
# alias: ip ~ Get my current global IP address
alias ip="dig +short myip.opendns.com @resolver1.opendns.com"

# alias: localip ~ Get my locally-set IP address
alias localip="ipconfig getifaddr en1"

# alias: whois ~ Run a whois lookup on a given URL
alias whois="whois -h whois-servers.net"

# alias: sniff ~ Sniff HTTP traffic
alias sniff="sudo ngrep -d 'en1' -t '^(GET|POST) ' 'tcp and port 80'"

# alias: httpdump ~ Dump all HTTP traffic
alias httpdump="sudo tcpdump -i en1 -n -s 0 -w - | grep -a -o -E \"Host\: .*|GET \/.*\""
