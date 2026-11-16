#!/system/bin/sh
# xguard run shield set <键> <值>   防护引擎高级设置（立即生效）
#   mount_mode auto|bind|overlay|zn|hfr   挂载方式（auto = 自动探测，见 lib.sh shield_method）
#   hide 0|1                              登记给 KSU/susfs 卸载列表（1 = 开了「卸载模块」的 App 里看不到 hosts，也就没有拦截）
#   hosts_max 10000~1000000               规则条数上限
#   proxy_yield 0|1                        代理服务运行时撤下 hosts（默认 0：hosts 和代理服务并存；1 = 旧行为，网络去广告全交给代理服务）
. "$XG_FDIR/lib.sh"
k=${1:-}; v=${2:-}
case "$k" in
  mount_mode) case "$v" in auto|bind|overlay|zn|hfr) ;; *) echo "取值：auto bind overlay zn hfr"; exit 2 ;; esac
    hosts_off; rm -f "$AD_DIR/method.overlay"; core_cfg_set $SHIELD mount_mode "$v"; reconcile ;;
  hide) case "$v" in 0|1) ;; *) echo "取值：0 或 1"; exit 2 ;; esac; core_cfg_set $SHIELD hide "$v"
    [ "$v" = 1 ] && shield_hide; [ "$v" = 0 ] && echo "已关闭；重启后完全恢复（已登记的卸载项要重启才会清掉）" ;;
  hosts_max) case "$v" in ''|*[!0-9]*) echo "需为整数"; exit 2 ;; esac
    [ "$v" -ge 10000 ] && [ "$v" -le 1000000 ] || { echo "范围 10000~1000000"; exit 2; }
    core_cfg_set $SHIELD hosts_max "$v"; hosts_build ;;
  proxy_yield) case "$v" in 0|1) ;; *) echo "取值：0 或 1"; exit 2 ;; esac
    core_cfg_set $SHIELD proxy_yield "$v"; reconcile ;;
  *) echo "用法: set mount_mode|hide|hosts_max|proxy_yield <值>"; exit 2 ;;
esac
shield_write_status
echo ok
