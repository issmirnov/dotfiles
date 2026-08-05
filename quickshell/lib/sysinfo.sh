#!/usr/bin/env bash
# One line of instantaneous system counters for the Quickshell bar's Sys singleton:
#   <cpu_idle> <cpu_total> <mem_used_pct> <temp_c> <net_rx_bytes> <net_tx_bytes>
# The QML side computes CPU% and net throughput as deltas between successive polls.
# All the fragile /proc + hwmon parsing lives here (one place, easy to test).

# --- CPU aggregate jiffies (/proc/stat first line: "cpu u n s idle iowait irq softirq steal ...") ---
read -r _ u n s idle iow irq sirq steal _ < /proc/stat
cpu_total=$(( u + n + s + idle + iow + irq + sirq + steal ))

# --- Memory used % = (MemTotal - MemAvailable) / MemTotal ---
mem_pct=$(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{ if (t>0) printf "%d", (t-a)*100/t; else print 0 }' /proc/meminfo)

# --- CPU package temperature (resolve coretemp by NAME; hwmonN index is not stable across boots) ---
temp_c=0
for h in /sys/class/hwmon/hwmon*; do
  [ -r "$h/name" ] || continue
  if [ "$(< "$h/name")" = coretemp ] && [ -r "$h/temp1_input" ]; then
    temp_c=$(( $(< "$h/temp1_input") / 1000 ))
    break
  fi
done

# --- Net bytes on the default-route interface (Destination 00000000 in /proc/net/route) ---
dev=$(awk '$2=="00000000"{print $1; exit}' /proc/net/route 2>/dev/null)
rx=0; tx=0
if [ -n "$dev" ] && [ -d "/sys/class/net/$dev/statistics" ]; then
  rx=$(< "/sys/class/net/$dev/statistics/rx_bytes")
  tx=$(< "/sys/class/net/$dev/statistics/tx_bytes")
fi

echo "$idle $cpu_total $mem_pct $temp_c $rx $tx"
