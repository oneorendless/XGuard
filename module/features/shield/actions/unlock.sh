#!/system/bin/sh
# xguard run shield unlock <包名>   单独解锁并记住；不带包名 = 临时全部解锁（下次 config/开机会重新锁）
. "$XG_FDIR/lib.sh"
if [ -n "${1:-}" ]; then splash_skip "$1"; else splash_unlock; fi
echo ok
