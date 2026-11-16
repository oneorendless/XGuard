#!/system/bin/sh
# $1 = 阶段（service / manual）：迁移旧配置 / 旧 hosts → 用现有规则（内置基线 + 缓存）立即生成并挂上 hosts →
#   后台拉起自动更新（等网络 + 重试，不阻塞开机）→ 锁开屏缓存，写 status.json
. "$XG_FDIR/lib.sh"
shield_migrate
shield_paused && { shield_write_status '临时暂停中'; exit 0; }
hosts_build        # 内置基线随模块分发：新装 / 升级后不联网也立即有规则
reconcile          # 先用现有规则挂上（开机不等网络）
shield_kick_update "${1:-service}"
splash_apply
sh "$XG_MODDIR/core/monitor.sh" start >/dev/null 2>&1
shield_write_status
exit 0
