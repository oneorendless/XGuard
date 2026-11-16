#!/system/bin/sh
# 只做分发：各阶段逻辑全部在 core/dispatch.sh 与 features/*/ 里
MODDIR=${0%/*}
exec sh "$MODDIR/core/dispatch.sh" emulated-soft-reboot
