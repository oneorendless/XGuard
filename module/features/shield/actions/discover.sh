#!/system/bin/sh
# xguard run shield discover [包名]   扫描疑似开屏广告缓存目录（只列候选，不锁定；App 里一键加入规则）
. "$XG_FDIR/lib.sh"
splash_discover "${1:-}" "${2:-8}"
