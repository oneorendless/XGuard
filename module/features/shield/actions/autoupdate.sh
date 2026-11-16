#!/system/bin/sh
# xguard run shield autoupdate [原因]   后台自动更新（start.sh / net 事件用 shield_kick_update 拉起，也可以手动跑）：
#   等网络（最多 10 分钟）→ 更新全部已启用规则源 → 还有源没成功就按 1 / 3 / 10 / 30 分钟重试 → 全部成功或用完次数退出。
#   进度写 $XG_DATA/shield/auto.state，App「规则源」页显示；同一时间只跑一个（$XG_RUN/shield-auto.pid）。
. "$XG_FDIR/lib.sh"
auto_running && [ "$(cat "$AUTO_PID" 2>/dev/null)" != "$$" ] && { echo "已有自动更新在运行"; exit 0; }
echo $$ >"$AUTO_PID"
trap 'rm -f "$AUTO_PID"' EXIT
log $SHIELD "自动更新开始（${1:-manual}）"
w=0
while ! shield_net_up; do
  [ $w -ge 600 ] && { auto_set gave_up 0 0; log $SHIELD "自动更新：10 分钟内没有网络，交给定时检查（tick）"; exit 1; }
  auto_set waiting_net 0 0; sleep 15; w=$((w+15))
done
n=0
for gap in 0 60 180 600 1800; do
  if [ "$gap" -gt 0 ]; then auto_set retry $(( $(date +%s) + gap )) "$n"; sleep "$gap"; fi
  n=$((n+1)); auto_set running 0 "$n"
  hosts_update force
  reconcile; shield_write_status
  src_missing || [ "$(prop_get "$META" result fail)" = fail ] || { auto_set done 0 "$n"; log $SHIELD "自动更新完成：第 $n 次，hosts $(hosts_rules) 条"; exit 0; }
done
auto_set gave_up 0 "$n"
log $SHIELD "自动更新：重试 $n 次仍有规则源没下载成功（见各源错误），之后由定时检查继续"
exit 1
