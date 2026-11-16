#!/system/bin/sh
# xguard run shield update   立即更新全部已启用规则源（忽略间隔，各源并行下载），重建并发布 hosts
. "$XG_FDIR/lib.sh"
if hosts_update force; then reconcile; shield_write_status; echo "ok $(prop_get "$META" result) $(hosts_rules) $(prop_get "$META" sources_ok 0)/$(prop_get "$META" sources_want 0)"
else shield_write_status; echo "fail $(prop_get "$META" result)"; exit 1; fi
