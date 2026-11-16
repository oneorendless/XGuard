#!/system/bin/sh
XG_ID=xguard
XG_MODDIR=${XG_MODDIR:-/data/adb/modules/$XG_ID}
XG_DATA=${XG_DATA:-/data/adb/$XG_ID}                 # 数据目录：卸载重装不丢
XG_CFG=$XG_DATA/config                   # settings.prop + 每个插件一个 <id>.prop
XG_STATE=$XG_DATA/state                  # 运行时状态（pid、计数、标记）
XG_LOG=$XG_DATA/logs
XG_RUN=$XG_DATA/run                      # FIFO / socket / 锁
XG_FEATURES=$XG_MODDIR/features
export XG_MODDIR XG_DATA XG_CFG XG_STATE XG_LOG XG_RUN XG_FEATURES

for _bb in /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox /data/adb/magisk/busybox; do
  [ -x "$_bb" ] && { XG_BB=$_bb; break; }
done
unset _bb
bb() { if [ -n "${XG_BB:-}" ]; then "$XG_BB" "$@"; else "$@"; fi; }

if [ -d /data/adb/ksu ]; then XG_ROOT=ksu
elif [ -d /data/adb/ap ]; then XG_ROOT=apatch
elif [ -d /data/adb/magisk ]; then XG_ROOT=magisk
else XG_ROOT=unknown; fi
