#!/usr/bin/env bash
# On-demand detail for the Quickshell stat-chip popups — one JSON object on stdout.
# Usage: sysdetail.sh <cpu|mem|temp|load|net>
# Only /usr/bin tools (ps/free/sensors/nvidia-smi/awk + /proc + hwmon): safe under
# qs's minimal PATH=/usr/local/bin:/usr/bin. No ~/.local/bin dependency.
set -u

sec_cpu() {
  # top 5 processes by CPU%
  ps -eo pcpu=,comm= --sort=-pcpu 2>/dev/null | head -5 | awk '
    BEGIN{ printf "{\"procs\":[" }
    { pct=$1; $1=""; sub(/^[ \t]+/,""); n=$0; gsub(/\\/,"\\\\",n); gsub(/"/,"\\\"",n)
      printf "%s{\"name\":\"%s\",\"pct\":%s}", (c++?",":""), n, pct+0 }
    END{ print "]}" }'
}

sec_mem() {
  awk '
    /^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} /^Cached:/{ca=$2}
    /^SwapTotal:/{st=$2} /^SwapFree:/{sf=$2}
    END{ printf "%d %d %d %d", (t-a)/1024, ca/1024, a/1024, (st-sf)/1024 }' /proc/meminfo \
  | { read -r used cached avail swap
      procs=$(ps -eo rss=,comm= --sort=-rss 2>/dev/null | head -5 | awk '
        { mb=$1/1024; $1=""; sub(/^[ \t]+/,""); n=$0; gsub(/\\/,"\\\\",n); gsub(/"/,"\\\"",n)
          printf "%s{\"name\":\"%s\",\"mb\":%d}", (c++?",":""), n, mb }')
      printf '{"used_mb":%d,"cached_mb":%d,"avail_mb":%d,"swap_mb":%d,"procs":[%s]}\n' \
        "$used" "$cached" "$avail" "$swap" "$procs"; }
}

sec_temp() {
  # collect priority-tagged rows: 0 = always shown (pkg/nvme/gpu), 1 = per-core (keep hottest 3)
  rows=""
  for h in /sys/class/hwmon/hwmon*; do
    [ -r "$h/name" ] || continue; nm=$(<"$h/name")
    case "$nm" in
      coretemp)
        [ -r "$h/temp1_input" ] && rows+="0|CPU pkg|$(( $(<"$h/temp1_input")/1000 ))|"$'\n'
        for f in "$h"/temp[2-9]_input "$h"/temp1[0-9]_input; do
          [ -r "$f" ] || continue
          lbl="${f%_input}_label"; l=$([ -r "$lbl" ] && cat "$lbl" || echo core)
          rows+="1|$l|$(( $(<"$f")/1000 ))|"$'\n'
        done ;;
      nvme)
        [ -r "$h/temp1_input" ] && rows+="0|NVMe|$(( $(<"$h/temp1_input")/1000 ))|"$'\n' ;;
    esac
  done
  # GPU temp + fan% via nvidia-smi (the fan field only appears on this row)
  g=$(nvidia-smi --query-gpu=temperature.gpu,fan.speed --format=csv,noheader,nounits 2>/dev/null | head -1)
  [ -n "$g" ] && rows+="0|GPU|${g%%,*}|${g##*, }"$'\n'

  { printf '%s' "$rows" | grep '^0|'
    printf '%s' "$rows" | grep '^1|' | sort -t'|' -k3 -nr | head -3; } \
  | awk -F'|' '
      BEGIN{ printf "{\"sensors\":[" }
      NF{ l=$2; gsub(/\\/,"\\\\",l); gsub(/"/,"\\\"",l)
          printf "%s{\"label\":\"%s\",\"c\":%s%s}", (c++?",":""), l, $3+0, ($4!=""?",\"fan\":" $4+0:"") }
      END{ print "]}" }'
}

sec_load() {
  read -r l1 l5 l15 _ < /proc/loadavg
  up=$(awk '{d=int($1/86400);h=int(($1%86400)/3600);m=int(($1%3600)/60)
             if(d)printf "%dd %dh",d,h; else if(h)printf "%dh %dm",h,m; else printf "%dm",m}' /proc/uptime)
  printf '{"l1":%s,"l5":%s,"l15":%s,"cores":%d,"uptime":"%s"}\n' "$l1" "$l5" "$l15" "$(nproc)" "$up"
}

sec_net() {
  # primary uplink = the real default-route dev (ip is authoritative; /proc/net/route hex as fallback)
  prim=$(ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
  [ -z "$prim" ] && prim=$(awk '$2=="00000000"{print $1; exit}' /proc/net/route 2>/dev/null)
  # "interesting" ifaces: operstate up, minus the veth/bridge/docker/vm-tap churn.
  # NOTE: keep virbr* — on this host the default route rides virbr0, so it's the real uplink.
  keep=""
  for d in /sys/class/net/*; do
    n=${d##*/}
    case "$n" in lo|veth*|br-*|docker*|vnet*|tap*) continue ;; esac
    [ -r "$d/operstate" ] && [ "$(<"$d/operstate")" = up ] || continue
    keep+=" $n "
  done
  [ -n "$prim" ] && case "$keep" in *" $prim "*) ;; *) keep+=" $prim " ;; esac   # ensure primary present
  # snapshot rx/tx bytes for kept ifaces, twice ~0.4s apart, for a rate
  snap() { awk -v keep="$keep" 'NR>2{ sub(/^ +/,""); i=index($0,":"); name=substr($0,1,i-1)
             if (index(keep," " name " ")) { split(substr($0,i+1),f," "); print name, f[1], f[9] } }' /proc/net/dev; }
  a=$(snap); sleep 0.4; b=$(snap)
  { printf '%s\n' "$a"; echo '==='; printf '%s\n' "$b"; } | awk -v prim="$prim" '
    $1=="==="{ phase=1; next }
    phase==0{ rx1[$1]=$2; tx1[$1]=$3; ord[n++]=$1 }
    phase==1{ rx2[$1]=$2; tx2[$1]=$3 }
    END{
      printf "{\"ifaces\":["
      for(i=0;i<n;i++){ nm=ord[i]; rxr=(rx2[nm]-rx1[nm])/0.4; txr=(tx2[nm]-tx1[nm])/0.4
        if(rxr<0)rxr=0; if(txr<0)txr=0
        g=nm; gsub(/\\/,"\\\\",g); gsub(/"/,"\\\"",g)
        printf "%s{\"name\":\"%s\",\"rx\":%d,\"tx\":%d}", (i?",":""), g, rxr, txr }
      printf "],\"primary\":\"%s\",\"rx_total\":%d,\"tx_total\":%d}\n", prim, rx2[prim]+0, tx2[prim]+0
    }'
}

case "${1:-}" in
  cpu)  sec_cpu ;;
  mem)  sec_mem ;;
  temp) sec_temp ;;
  load) sec_load ;;
  net)  sec_net ;;
  *) echo '{"error":"usage: sysdetail.sh <cpu|mem|temp|load|net>"}'; exit 2 ;;
esac
