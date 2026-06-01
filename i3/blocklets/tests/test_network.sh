#!/usr/bin/env bash
DIR=$(dirname "$0"); . "$DIR/assert.sh"; S="$DIR/../network"

# no default route -> urgent "no net"
out=$(NET_TEST_IF= bash "$S"); ec=$?
assert_eq "down full"  "no net"  "$(sed -n 1p <<<"$out")"
assert_eq "down color" "#FF1744" "$(sed -n 3p <<<"$out")"
assert_eq "down exit"  "33"      "$ec"

# vpn iface
out=$(NET_TEST_IF=tun0 bash "$S")
assert_eq "vpn full"  "VPN"     "$(sed -n 1p <<<"$out")"
assert_eq "vpn color" "#00B8D4" "$(sed -n 3p <<<"$out")"

# wifi strong signal
out=$(NET_TEST_IF=wlo1 NET_TEST_WIRELESS=1 NET_TEST_SSID="MyAP-5G" NET_TEST_SIGNAL=72 bash "$S")
assert_eq "wifi full"  "MyAP-5G 72%" "$(sed -n 1p <<<"$out")"
assert_eq "wifi color" "#FFD600"     "$(sed -n 3p <<<"$out")"

# wifi weak signal -> orange
out=$(NET_TEST_IF=wlo1 NET_TEST_WIRELESS=1 NET_TEST_SSID="Far" NET_TEST_SIGNAL=22 bash "$S")
assert_eq "wifi weak color" "#FF6D00" "$(sed -n 3p <<<"$out")"

# wired -> quiet LAN
out=$(NET_TEST_IF=enp8s0f0 NET_TEST_WIRELESS=0 bash "$S")
assert_eq "wired full"  "LAN"     "$(sed -n 1p <<<"$out")"
assert_eq "wired color" "#00C853" "$(sed -n 3p <<<"$out")"

# wireguard iface also classified as VPN
out=$(NET_TEST_IF=wg0 bash "$S")
assert_eq "vpn wg full"  "VPN"     "$(sed -n 1p <<<"$out")"
assert_eq "vpn wg color" "#00B8D4" "$(sed -n 3p <<<"$out")"

# wifi with empty SSID (hidden network) -> "wifi" fallback label
out=$(NET_TEST_IF=wlo1 NET_TEST_WIRELESS=1 NET_TEST_SSID="" NET_TEST_SIGNAL=65 bash "$S")
assert_eq "wifi hidden ssid" "wifi 65%" "$(sed -n 1p <<<"$out")"
finish
