#!/system/bin/sh
set -eu
export XG_MODDIR=${XG_MODDIR:-/data/adb/modules/xguard}
export XG_DATA=$(mktemp -d /data/local/tmp/xguard-splash-network.XXXXXX)
export XG_FDIR=$XG_MODDIR/features/shield
test_dir=$XG_DATA
iptables_bin=$(command -v iptables)
ip6tables_bin=$(command -v ip6tables)
stat_bin=$(command -v stat)
cleanup() {
  for binary in "$iptables_bin" "$ip6tables_bin"; do
    for chain in XGT_OUTPUT XGT_SPLASH XGT_SPLASH_HOST; do "$binary" -w -F "$chain" 2>/dev/null || :; done
    for chain in XGT_OUTPUT XGT_SPLASH XGT_SPLASH_HOST; do "$binary" -w -X "$chain" 2>/dev/null || :; done
  done
  rm -rf "$test_dir"
}
trap cleanup EXIT
sed 's/XGUARD_SPLASH/XGT_SPLASH/g' "$XG_FDIR/lib.sh" >"$test_dir/lib.sh"
. "$test_dir/lib.sh"
test_paused=0
test_enabled=1
feat_enabled() { [ "$test_enabled" = 1 ]; }
shield_paused() { [ "$test_paused" = 1 ]; }
stat() {
  case "$*" in
    '-c %u /data/user/0/com.chaoxing.mobile') echo 11001 ;;
    '-c %u /data/user/0/com.chinamobile.mcloud') echo 11002 ;;
    '-c %u /data/user/0/com.xunlei.downloadprovider') echo 11003 ;;
    *) "$stat_bin" "$@" ;;
  esac
}
test_iptables() {
  binary=$1; shift
  [ "$1" = -w ] && shift
  operation=$1; chain=$2; shift 2
  [ "$chain" != OUTPUT ] || chain=XGT_OUTPUT
  "$binary" -w "$operation" "$chain" "$@"
}
iptables() { test_iptables "$iptables_bin" "$@"; }
ip6tables() { test_iptables "$ip6tables_bin" "$@"; }
sync_rules() { splash_network_sync || exit 1; }
for binary in "$iptables_bin" "$ip6tables_bin"; do
  ! "$binary" -w -S XGT_OUTPUT >/dev/null 2>&1
  "$binary" -w -N XGT_OUTPUT
done
mkdir -p "$AD_DIR"
: >"$ALLOW"
sync_rules
for binary in "$iptables_bin" "$ip6tables_bin"; do
  "$binary" -w -C XGT_OUTPUT -j XGT_SPLASH
  for test_uid in 11001 11002 11003; do
    "$binary" -w -C XGT_SPLASH -p tcp -m owner --uid-owner "$test_uid" -j XGT_SPLASH_HOST
  done
  [ "$("$binary" -w -S XGT_SPLASH | grep -c '^-A ')" = 3 ]
  "$binary" -w -C XGT_SPLASH_HOST -p tcp -m string --algo kmp --string ad.mcloud.139.com -j REJECT --reject-with tcp-reset
done
before_rules=$("$iptables_bin" -w -S XGT_SPLASH_HOST)
sync_rules
[ "$before_rules" = "$("$iptables_bin" -w -S XGT_SPLASH_HOST)" ]
echo com.chinamobile.mcloud >"$SKIP"
sync_rules
! "$iptables_bin" -w -C XGT_SPLASH -p tcp -m owner --uid-owner 11002 -j XGT_SPLASH_HOST 2>/dev/null
"$iptables_bin" -w -C XGT_SPLASH -p tcp -m owner --uid-owner 11001 -j XGT_SPLASH_HOST
printf '%s\n' 'ad.mcloud.139.com' '*.buluken.com' >"$ALLOW"
sync_rules
for binary in "$iptables_bin" "$ip6tables_bin"; do
  ! "$binary" -w -C XGT_SPLASH_HOST -p tcp -m string --algo kmp --string ad.mcloud.139.com -j REJECT --reject-with tcp-reset 2>/dev/null
  ! "$binary" -w -C XGT_SPLASH_HOST -p tcp -m string --algo kmp --string bid.buluken.com -j REJECT --reject-with tcp-reset 2>/dev/null
done
test_paused=1
sync_rules
for binary in "$iptables_bin" "$ip6tables_bin"; do
  ! "$binary" -w -S XGT_SPLASH >/dev/null 2>&1
  ! "$binary" -w -S XGT_SPLASH_HOST >/dev/null 2>&1
done
test_paused=0
sync_rules
test_enabled=0
sync_rules
! "$iptables_bin" -w -S XGT_SPLASH >/dev/null 2>&1
test_enabled=1
printf '%s\n' com.chaoxing.mobile com.chinamobile.mcloud com.xunlei.downloadprovider >"$SKIP"
sync_rules
! "$iptables_bin" -w -S XGT_SPLASH >/dev/null 2>&1
: >"$SKIP"
sync_rules
splash_network_off
for binary in "$iptables_bin" "$ip6tables_bin"; do
  ! "$binary" -w -S XGT_SPLASH >/dev/null 2>&1
  ! "$binary" -w -S XGT_SPLASH_HOST >/dev/null 2>&1
  [ "$("$binary" -w -S XGT_OUTPUT | grep -c '^-' )" = 1 ]
done
echo 'PASS: IPv4/IPv6 UID scope, reuse, app skip, exact/wildcard allow, pause, disable, all skipped, cleanup'
