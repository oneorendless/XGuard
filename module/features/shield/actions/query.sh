#!/system/bin/sh
# xguard run shield query <域名>   这个域名现在是否被 hosts 拦截（来源 / 放行 / 自定义）
. "$XG_FDIR/lib.sh"
valid_domain "${1:-}" || { echo "域名无效：${1:-}"; exit 2; }
activity_record "$1" query control-panel
hosts_query "$1"
