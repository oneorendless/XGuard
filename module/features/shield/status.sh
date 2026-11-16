#!/system/bin/sh
# 一行摘要（5 秒内返回）；顺带刷新 status.json
. "$XG_FDIR/lib.sh"
s=$(shield_summary)
shield_write_status "$s"
echo "$s"
