#!/system/bin/sh
# 卸载：撤下 hosts、HTTPDNS 规则和开屏锁；数据目录默认保留
XG_MODDIR=${0%/*}; export XG_MODDIR
. "$XG_MODDIR/core/lib.sh"
sh "$XG_MODDIR/core/xguardd.sh" stop
for id in $(feat_list); do feat_run "$id" stop uninstall; done
[ "$(settings_get keep_data_on_uninstall 1)" = 0 ] && rm -rf "$XG_DATA"
exit 0
