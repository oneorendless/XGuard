#!/bin/sh
set -eu
XG_MODDIR=$(cd "$(dirname "$0")/../module" && pwd)
XG_FDIR=$XG_MODDIR/features/shield
XG_DATA=$(mktemp -d)
trap 'rm -rf "$XG_DATA"' EXIT
. "$XG_FDIR/lib.sh"
set +eu
mkdir -p "$XG_LOG" "$XG_RUN" "$XG_STATE"
sed '2d' "$XG_FDIR/actions/app_allowlist.sh" >"$AD_DIR/app-allowlist-test.sh"

mall=com.xiaomi.shop
community=com.xiaomi.vipaccount
chaoxing=com.chaoxing.mobile
cloud=com.chinamobile.mcloud
feat_enabled() { [ "$enabled" = 1 ]; }
shield_paused() { [ "$paused" = 1 ]; }
proxy_running() { return 1; }
guard_wanted() { return 0; }
hosts_on() { fail 'touched shared hosts'; }
hosts_off() { fail 'touched shared hosts'; }
stat() {
  case "$*" in
    *"/$mall") echo 10001 ;;
    *"/$community") echo 10002 ;;
    *"/$chaoxing") echo 10003 ;;
    *"/$cloud") echo 10004 ;;
    *) return 1 ;;
  esac
}
iptables() {
  echo "$*" >>"$AD_DIR/iptables"
  case "$2" in -C|-D) return 1 ;; esac
  case "$*" in *'--uid-owner 10002 -j RETURN') [ "$fail_guard" != 1 ] ;; *) return 0 ;; esac
}
ip6tables() { iptables "$@"; }
splash_target() { _sb=$AD_DIR/cache; _st=$_sb/$1/$2; }
splash_unlock_one() {
  [ "$fail_unlock" != 1 ] || return 1
  echo "${1#"$AD_DIR/cache/"}" >>"$AD_DIR/unlocks"
}
splash_lock_one() { echo "${2#"$AD_DIR/cache/"}" >>"$AD_DIR/locks"; }
log() { :; }
fail() { echo "FAIL: $*" >&2; exit 1; }
sync_apps() (
  . "$AD_DIR/app-allowlist-test.sh"
)

enabled=1 paused=0 fail_guard=0 fail_unlock=0
printf '%s cache\n' "$mall" "$community" >"$AD_DIR/locked.list"
printf '%s cache\n' "$mall" "$community" >"$USER_RULES"
printf '%s\n' "$community" >"$SKIP"
sync_apps "$mall" "$chaoxing" "$mall" >/dev/null || fail 'could not set allowlist'
[ "$(wc -l <"$APP_ALLOW")" -eq 2 ] || fail 'did not deduplicate'
grep -Fxq "$mall/cache" "$AD_DIR/unlocks" || fail 'did not unlock selected app'
grep -Fxq "$community cache" "$AD_DIR/locked.list" || fail 'unlocked other app'
guard_first=$(grep -m1 -F -- '-A XGUARD_HTTPDNS' "$AD_DIR/iptables")
case "$guard_first" in *'--uid-owner 10001 -j RETURN') ;; *) fail 'guard exemption must precede rejects' ;; esac
grep -Fq -- '-A XGUARD_HTTPDNS -d 203.107.1.0/24' "$AD_DIR/iptables" || fail 'HTTPDNS blocking was lost'
grep -Fq -- '-A XGUARD_SPLASH -p tcp -m owner --uid-owner 10004' "$AD_DIR/iptables" || fail 'other app lost splash protection'
if grep -Fq -- '-A XGUARD_SPLASH -p tcp -m owner --uid-owner 10003' "$AD_DIR/iptables"; then fail 'selected app still has splash protection'; fi

fail_guard=1
if sync_apps "$mall" "$community" >/dev/null; then fail 'failed firewall update reported success'; fi
app_allowlisted "$community" && fail 'firewall failure saved new selection'
app_allowlisted "$chaoxing" || fail 'firewall failure lost previous selection'
fail_guard=0 fail_unlock=1
if sync_apps "$mall" "$community" >/dev/null; then fail 'failed unlock reported success'; fi
app_allowlisted "$community" && fail 'cache failure saved new selection'
grep -Fxq "$community cache" "$AD_DIR/locked.list" || fail 'failed unlock was dropped from lock tracking'
fail_unlock=0

: >"$AD_DIR/iptables"
sync_apps >/dev/null || fail 'could not remove allowlist'
[ ! -s "$APP_ALLOW" ] || fail 'allowlist not emptied'
grep -Fxq "$mall/cache" "$AD_DIR/locks" || fail 'did not restore cache protection'
cache_skipped "$community" || fail 'legacy cache unlock was lost'
grep -Fq -- '-A XGUARD_SPLASH -p tcp -m owner --uid-owner 10003' "$AD_DIR/iptables" || fail 'did not restore splash firewall rule'

paused=1
: >"$AD_DIR/iptables"
sync_apps "$mall" >/dev/null || fail 'could not save while paused'
if grep -Eq -- '-[AI] ' "$AD_DIR/iptables"; then fail 'changed active protection while paused'; fi
echo 'PASS: Root cache, UID exemptions, rollback, legacy cache unlock, removal and pause'
