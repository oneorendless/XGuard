#!/system/bin/sh
set -eu
export XG_MODDIR=${XG_MODDIR:-/data/adb/modules/xguard}
export XG_FDIR=$XG_MODDIR/features/shield
. "$XG_FDIR/lib.sh"
fixture=$(mktemp -d /data/local/tmp/xguard-stats.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
stats_json quick >"$fixture/quick.json" || exit 1
[ "$(core_json_get "$fixture/quick.json" hosts_rules)" = "$(hosts_rules)" ]
[ "$(core_json_get "$fixture/quick.json" locked_count_cached)" = 1 ]
[ "$(core_json_get "$fixture/quick.json" source_list)" = '[]' ]
[ "$(core_json_get "$fixture/quick.json" mode)" = "$(shield_mode)" ]
real_ad=$AD_DIR
AD_DIR=$fixture
stats_json quick >"$fixture/missing.json" || exit 1
[ "$(core_json_get "$fixture/missing.json" splash_locked_apps)" = '' ]
[ "$(core_json_get "$fixture/missing.json" locked_checked_at)" = 0 ]
printf '{"splash_locked_apps":7,"updated_at":123}\n' >"$fixture/status.json"
stats_json quick >"$fixture/cached.json" || exit 1
[ "$(core_json_get "$fixture/cached.json" splash_locked_apps)" = 7 ]
[ "$(core_json_get "$fixture/cached.json" locked_checked_at)" = 123 ]
printf '{"splash_locked_apps":"bad","updated_at":"bad"}\n' >"$fixture/status.json"
stats_json quick >"$fixture/invalid.json" || exit 1
[ "$(core_json_get "$fixture/invalid.json" splash_locked_apps)" = '' ]
[ "$(core_json_get "$fixture/invalid.json" locked_checked_at)" = 0 ]
AD_DIR=$real_ad
echo 'PASS: quick stats, live hosts mode/rules, missing/invalid snapshot and cached lock count'
