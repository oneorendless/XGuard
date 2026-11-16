#!/system/bin/sh
set -eu
export XG_MODDIR=/data/adb/modules/xguard
fixture=/data/data/com.xuan.xguard/cache/xguard-scan-depth-085
[ ! -e "$fixture" ] || { echo 'Fixture already exists'; exit 1; }
mkdir -p "$fixture/a/b/c/d/e/f/g/splash_test"
trap 'rm -rf /data/data/com.xuan.xguard/cache/xguard-scan-depth-085' EXIT
cli=$XG_MODDIR/system/bin/xguard
sh "$cli" run shield discover com.xuan.xguard 12 | grep -q 'xguard-scan-depth-085/a/b/c/d/e/f/g/splash_test'
! sh "$cli" run shield discover com.xuan.xguard 6 | grep -q 'xguard-scan-depth-085/a/b/c/d/e/f/g/splash_test'
if sh "$cli" run shield discover com.xuan.xguard 99; then exit 1; fi
echo 'PASS: deep directory discovered at 12 layers, excluded at 6, invalid depth rejected'
