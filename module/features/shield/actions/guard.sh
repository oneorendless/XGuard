#!/system/bin/sh
# xguard run shield guard [on|off]   HTTPDNS IP 拦截（iptables 拒绝 rules/httpdns.ip 里的地址的 TCP 80/443），v0.2.26 起默认关
#   不带参数：输出 {"guard":0|1,"active":0|1}
. "$XG_FDIR/lib.sh"
case "${1:-}" in
  on) core_cfg_set $SHIELD guard 1; if proxy_running; then echo "ok proxy"; elif guard_on; then log $SHIELD "HTTPDNS IP 拦截已开启"; echo ok; else echo "iptables 不可用"; exit 1; fi ;;
  off) core_cfg_set $SHIELD guard 0; guard_off; log $SHIELD "HTTPDNS IP 拦截已关闭"; echo ok ;;
  *) printf '{"guard":%s,"active":%s}\n' "$(core_cfg_get $SHIELD guard 0)" "$(guard_active && echo 1 || echo 0)" ;;
esac
shield_write_status
