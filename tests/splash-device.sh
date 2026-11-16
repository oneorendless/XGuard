#!/system/bin/sh
# Run on a rooted Android device; all targets are isolated under a test directory.
set -eu
export XG_MODDIR=${XG_MODDIR:-/data/adb/modules/xguard}
export XG_FDIR=$XG_MODDIR/features/shield
export XG_DATA=$(mktemp -d /data/local/tmp/xguard-splash-test-085.XXXXXX)
. "$XG_FDIR/lib.sh"
mkdir -p "$XG_RUN" "$XG_DATA/apps/com.test.one" "$XG_DATA/apps/com.test.two"
feat_enabled() { return 0; }
log() { :; }
splash_network_sync() { :; }
skipped() { [ -f "$SKIP" ] && grep -Fxq "$1" "$SKIP"; }
splash_target() { _sb=$XG_DATA/apps/$1; _st=$_sb/$2; }
splash_rules() { cat "$USER_RULES" 2>/dev/null | awk '!seen[$0]++'; }
: >"$USER_RULES"
valid_rel '../bad' && exit 10
valid_rel '.' && exit 11
valid_rel 'files/./bad' && exit 12
valid_pkg 'com.test.one' || exit 13
rule_add com.test.one cache/parent/splash
[ -d "$XG_DATA/apps/com.test.one/cache/parent" ]
splash_is_locked "$XG_DATA/apps/com.test.one/cache/parent/splash"
[ "$(splash_locked_count)" = 1 ]
# A legacy empty file must not count as immutable protection.
mkdir -p "$XG_DATA/apps/com.test.two/cache"
: >"$XG_DATA/apps/com.test.two/cache/weak"; chmod 400 "$XG_DATA/apps/com.test.two/cache/weak"
printf '%s\n' 'com.test.two cache/weak' >>"$USER_RULES"
[ "$(splash_locked_count)" = 1 ]
splash_states | grep -q 'weak$'
# Exact duplicates stay one rule; edits cannot clobber a concurrent edit.
rule_add com.test.one cache/parent/splash
[ "$(awk '$1=="com.test.one" && $2=="cache/parent/splash" {n++} END {print n+0}' "$USER_RULES")" = 1 ]
rule_add com.test.one cache/a & p1=$!
rule_add com.test.one cache/b & p2=$!
wait "$p1"; wait "$p2"
grep -q 'cache/a$' "$USER_RULES"; grep -q 'cache/b$' "$USER_RULES"
rule_remove com.test.one cache/a
! splash_is_locked "$XG_DATA/apps/com.test.one/cache/a"
splash_skip com.test.one
[ "$(splash_locked_count)" = 0 ]
splash_relock com.test.one
[ "$(splash_locked_count)" = 1 ]
# A symlink in an app-controlled ancestor cannot redirect a Root deletion.
mkdir -p "$XG_DATA/outside"; echo keep >"$XG_DATA/outside/keep"
ln -s "$XG_DATA/outside" "$XG_DATA/apps/com.test.one/link"
! splash_lock_one "$XG_DATA/apps/com.test.one" "$XG_DATA/apps/com.test.one/link/ad"
[ -s "$XG_DATA/outside/keep" ]
splash_unlock
echo 'PASS: incremental edits, real counts, weak state, concurrent edits, unlock/relock, symlink boundary'
