#!/system/bin/sh
# xguard run shield hits   开屏规则命中情况（JSON，App/WebUI 用）
. "$XG_FDIR/lib.sh"
splash_hits_json "${1:-}"
