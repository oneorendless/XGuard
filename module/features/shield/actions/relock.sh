#!/system/bin/sh
# xguard run shield relock <包名>   撤销单独解锁，重新按规则锁定
. "$XG_FDIR/lib.sh"
[ -n "${1:-}" ] || { echo "用法: relock <包名>"; exit 1; }
splash_relock "$1"; echo ok
