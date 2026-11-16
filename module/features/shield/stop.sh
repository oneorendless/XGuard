#!/system/bin/sh
# 关闭防护引擎：撤下 hosts，关 HTTPDNS IP 拦截，解锁全部开屏缓存（用户单独解锁名单保留）
. "$XG_FDIR/lib.sh"
sh "$XG_MODDIR/core/monitor.sh" stop >/dev/null 2>&1
if auto_running; then
  _auto_pid=$(cat "$AUTO_PID")
  case "$(tr '\0' ' ' <"/proc/$_auto_pid/cmdline" 2>/dev/null)" in *autoupdate.sh*) kill "$_auto_pid" 2>/dev/null ;; esac
fi
rm -f "$AUTO_PID"
hosts_off
guard_off
splash_unlock
# 关闭后自查：hosts 还在哪个命名空间 / iptables 还有本插件规则，写日志（App「防护引擎日志」可见）
_r=$(hosts_residue); _g=$(guard_residue)
if [ "${_r:-0}" -gt 0 ] || [ -n "$_g" ]; then log $SHIELD "关闭后仍有残留：hosts 命名空间 ${_r:-0} 个 ${_g}"; else log $SHIELD "关闭完成：hosts 已全部卸载，iptables 无残留"; fi
shield_write_status "已关闭"
exit 0
