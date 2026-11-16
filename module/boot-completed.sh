#!/system/bin/sh
# 只做分发：逻辑全部在调度调度器与防护引擎插件中
MODDIR=${0%/*}
( sh "$MODDIR/core/app_fallback.sh" "$MODDIR" ) </dev/null >/dev/null 2>&1 &
exec sh "$MODDIR/core/dispatch.sh" boot-completed
