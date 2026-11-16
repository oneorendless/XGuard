#!/system/bin/sh
# 管理器里的「执行」按钮：打印防护引擎状态
XG_MODDIR=${0%/*}; export XG_MODDIR
echo "防护引擎"; echo
sh "$XG_MODDIR/system/bin/xguard" list
echo; echo "守护进程：$(sh "$XG_MODDIR/core/xguardd.sh" status)"
am start -n com.xuan.xguard/.MainActivity >/dev/null 2>&1
