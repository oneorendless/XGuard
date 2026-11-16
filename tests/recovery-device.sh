#!/system/bin/sh
# Run on Android against the supplied module tree; all writes use a disposable fixture.
set -e
original=${XG_MODDIR:-/data/adb/modules/xguard}
fixture=$(mktemp -d /data/local/tmp/xguard-recovery.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/module/features" "$fixture/module/core"
cp -R "$original/features/shield" "$fixture/module/features/"
cp "$original/core/"*.sh "$fixture/module/core/"
export XG_MODDIR=$fixture/module XG_DATA=$fixture/data
export XG_FDIR=$XG_MODDIR/features/shield
# Override only external side effects in the disposable copied module.
cat >>"$XG_FDIR/lib.sh" <<'STUBS'
hosts_mounted() { return 1; }
hosts_publish() { :; }
reconcile() { echo reconciled >>"$AD_DIR/test-events"; }
splash_apply() { echo splash >>"$AD_DIR/test-events"; }
splash_network_sync() { :; }
shield_write_status() { :; }
recovery_watchdog_start() { :; }
STUBS
. "$XG_FDIR/lib.sh"
# Suppress monitor process startup in the fixture.
printf '#!/system/bin/sh\nexit 0\n' >"$XG_MODDIR/core/monitor.sh"
core_init_dirs
# Keep the fixture small and deterministic; never touch real namespaces or firewall.
printf 'baseline|1|Fixture|Fixture|builtin:rules/test.list|1\n' >"$CATALOG"
printf 'old.example.test\nshared.example.test\n' >"$XG_FDIR/rules/test.list"
: >"$XG_FDIR/rules/splash-domains.list"
hosts_build
inode=$(stat -c %i "$HOSTS_SRC")
: >"$fixture/empty"
recovery_diff "$fixture/empty" "$HOSTS_SRC" >"$fixture/diff"
[ "$(prop_get "$fixture/diff" added)" = 2 ]
recovery_stage
printf 'new.example.test\n' >"$SRC_DIR/custom_fixture.list"
# Snapshot sources as well as effective hosts, then change one source deterministically.
printf 'test|1|Fixture|Fixture|https://invalid.test|1\n' >"$CATALOG"
printf 'old.example.test\nshared.example.test\n' >"$SRC_DIR/test.list"
hosts_build
recovery_stage
printf 'new.example.test\nshared.example.test\n' >"$SRC_DIR/test.list"
hosts_build
recovery_commit
[ "$(prop_get "$RECOVERY/last-update" added)" = 1 ]
[ "$(prop_get "$RECOVERY/last-update" removed)" = 1 ]
sh "$XG_FDIR/actions/allow.sh" add shared.example.test
[ -f "$RECOVERY/domain-undo/after" ]
! grep -q '^0.0.0.0 shared.example.test$' "$HOSTS_SRC"
domain_undo
grep -q '^0.0.0.0 shared.example.test$' "$HOSTS_SRC"
[ ! -d "$RECOVERY/domain-undo" ]
sh "$XG_FDIR/actions/block.sh" add user.example.test
recovery_rollback
grep -q '^0.0.0.0 old.example.test$' "$HOSTS_SRC"
grep -q '^0.0.0.0 user.example.test$' "$HOSTS_SRC"
! grep -q '^0.0.0.0 new.example.test$' "$HOSTS_SRC"
[ "$(stat -c %i "$HOSTS_SRC")" = "$inode" ]
[ "$(cat "$RECOVERY/update-hold")" -gt "$(date +%s)" ]
# Exercise the complete updater without external network access.
hosts_fetch_one() { printf 'downloaded.example.test\nshared.example.test\n' >"$2"; }
hosts_update force
grep -q '^0.0.0.0 downloaded.example.test$' "$HOSTS_SRC"
[ "$(prop_get "$RECOVERY/last-update" added)" = 1 ]
[ "$(prop_get "$RECOVERY/last-update" removed)" = 1 ]
[ ! -f "$RECOVERY/update-hold" ]
last_ok=$(prop_get "$META" last_ok)
current=$(cksum "$HOSTS_SRC")
hosts_fetch_one() { return 1; }
if hosts_update force; then echo 'FAIL: failed source reported success'; exit 1; fi
[ "$current" = "$(cksum "$HOSTS_SRC")" ]
[ "$(prop_get "$META" last_ok)" = "$last_ok" ]
[ ! -d "$XG_RUN/recovery-rules.lock" ]
[ ! -d "$XG_RUN/shield-update.lock" ]
# Selection mismatch must fail without changing hosts.
before=$(cksum "$HOSTS_SRC")
core_cfg_set shield sources other
printf 'other|1|Other|Other|https://other.test|1\n' >>"$CATALOG"
if recovery_rollback; then echo 'FAIL: selection mismatch accepted'; exit 1; fi
[ "$before" = "$(cksum "$HOSTS_SRC")" ]
core_cfg_set shield sources test
# Detect external edits before undo.
echo external.example.test >>"$ALLOW"
if domain_undo; then echo 'FAIL: external edit overwritten'; exit 1; fi
# Recursive known-source action must not delete its parent's rules mutex.
(
  recovery_lock rules
  sh "$XG_FDIR/actions/sources.sh" add https://invalid.test
  [ -d "$XG_RUN/recovery-rules.lock" ]
)
[ ! -d "$XG_RUN/recovery-rules.lock" ]
# Expiry respects manual disable; restoring while enabled invokes reconciliation.
settings_set feature.shield.enabled 0
echo 1 >"$PAUSE_FILE"
recovery_control expire
[ ! -f "$PAUSE_FILE" ]
rm -f "$AD_DIR/test-events"
settings_set feature.shield.enabled 1
echo 1 >"$PAUSE_FILE"
recovery_control expire
grep -q reconciled "$AD_DIR/test-events"
echo 'PASS: diff, snapshot/rollback, domain preservation/undo, source update success/failure, selection conflict, inode preservation, recursive mutex, pause expiry/manual disable'
