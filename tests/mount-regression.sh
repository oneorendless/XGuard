#!/bin/sh
set -eu
XG_MODDIR=$(cd "$(dirname "$0")/../module" && pwd)
XG_FDIR=$XG_MODDIR/features/shield
XG_DATA=$(mktemp -d)
trap 'rm -rf "$XG_DATA"' EXIT
. "$XG_FDIR/lib.sh"
set +u
mkdir -p "$AD_DIR" "$XG_LOG" "$XG_RUN" "$XG_STATE"
printf '# XGuard test\n' >"$HOSTS_SRC"

fail() { echo "FAIL: $*" >&2; exit 1; }
feat_enabled() { return 0; }
shield_paused() { return 1; }
hosts_set_perm() { return 0; }
shield_hide() { return 0; }
shield_live_overlay() { return 1; }
shield_ns_targets() { printf '101\n202\n'; }
shield_netd_pid() { echo 101; }
shield_ns_pid() { echo 202; }
shield_view() { test -e "$AD_DIR/view.$1"; }
shield_nsrun() { echo 'simulated mount error' >&2; return 32; }

if shield_mount_try 101 bind mount 2>"$AD_DIR/result"; then fail 'failed mount returned success'; fi
grep -q 'bind pid=101 ns=.* rc=32' "$AD_DIR/result" || fail 'missing exit code or namespace'
touch "$AD_DIR/view.101"
if hosts_views_mounted; then fail 'one target is not all targets'; fi
rm "$AD_DIR/view.101"

bind_mount_all() { echo bind >>"$AD_DIR/attempts"; [ "$bind_ok" = yes ] && touch "$AD_DIR/view.101" "$AD_DIR/view.202"; }
overlay_mount() {
  echo overlay >>"$AD_DIR/attempts"
  [ "$overlay_ok" = yes ] && { touch "$AD_DIR/view.101" "$AD_DIR/view.202"; return 0; }
  echo 'simulated overlay failure' >&2
  return 1
}
shield_preferred_method() { echo "$preferred"; }
core_cfg_get() { echo "$configured"; }
preferred=bind configured=auto bind_ok=yes overlay_ok=no
touch "$AD_DIR/method.overlay"
hosts_on || fail 'stale marker prevented bind'
test ! -e "$AD_DIR/method.overlay" || fail 'stale marker not cleared'
test "$(cat "$AD_DIR/attempts")" = bind || fail 'auto did not start with bind'

rm "$AD_DIR/view.101" "$AD_DIR/view.202" "$AD_DIR/attempts"
preferred=overlay configured=overlay
hosts_on || fail 'explicit overlay did not fall back to bind'
test "$(tr '\n' ' ' <"$AD_DIR/attempts")" = 'overlay bind ' || fail 'wrong fallback order'
test "$(mount_fallback)" = bind_after_overlay_fail || fail 'missing fallback state'
grep -q 'simulated overlay failure' "$AD_DIR/mount.err" || fail 'missing failure stderr'

rm "$AD_DIR/view.101" "$AD_DIR/view.202" "$AD_DIR/attempts"
preferred=bind configured=auto bind_ok=no overlay_ok=yes
hosts_on || fail 'auto did not fall back to overlay'
test "$(tr '\n' ' ' <"$AD_DIR/attempts")" = 'bind overlay ' || fail 'wrong auto fallback order'
test "$(mount_fallback)" = overlay_after_bind_fail || fail 'missing auto fallback state'
echo 'PASS: stale marker, both fallback orders, all-target validation and diagnostics'
