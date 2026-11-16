#!/system/bin/sh
set -eu
iptables -w -t nat -I OUTPUT 1 -d 10.231.0.1/32 -p udp --dport 53 -m comment --comment XGUARD_VPN_TEST -j ACCEPT
trap 'iptables -w -t nat -D OUTPUT -d 10.231.0.1/32 -p udp --dport 53 -m comment --comment XGUARD_VPN_TEST -j ACCEPT' EXIT
/data/local/tmp/xguard-dns-probe
