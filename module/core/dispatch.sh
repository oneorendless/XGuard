#!/system/bin/sh
STAGE=$1
XG_MODDIR=$(cd "${0%/*}/.." && pwd)
export XG_MODDIR
. "$XG_MODDIR/core/lib.sh"
core_init_dirs
core_migrate

bootguard() {
  _cnt=$XG_STATE/boot.count
  case "$STAGE" in
    post-fs-data|late-load)
      _n=$(cat "$_cnt" 2>/dev/null); case "$_n" in ''|*[!0-9]*) _n=0 ;; esac
      _n=$((_n + 1)); echo $_n >"$_cnt"
      _max=$(settings_get bootguard.max 3)
      core_track_changes
      if [ $_n -gt "$_max" ] && [ ! -f "$XG_STATE/safe_mode" ]; then
        _b=$(core_blame_candidate)
        if [ -n "$_b" ] && [ "$(settings_get core.brick_stepwise 1)" = 1 ]; then
          echo "连续 $_n 次未完成开机，疑似最近改动的「$(feat_meta "$_b" name "$_b")」，已临时禁用" >"$XG_STATE/brick.$_b"
          echo 1 >"$_cnt"
          log core "防砖：禁用 $_b（连续 $_n 次未完成开机）"
        else
          touch "$XG_STATE/safe_mode" "$XG_MODDIR/skip_mount"
          log core "连续 $_n 次未完成开机，进入安全模式"
        fi
      fi ;;
    boot-completed)
      echo 0 >"$_cnt" ;;
  esac
}
bootguard

if [ -f "$XG_STATE/safe_mode" ]; then
  log core "安全模式：跳过 $STAGE（在 WebUI 或 'xguard safe off' 退出）"
  exit 0
fi

[ "$STAGE" = service ] && sh "$XG_MODDIR/core/conflict.sh"

run_stage() {
  for id in $(feat_for_stage "${1:-$STAGE}"); do
    feat_enabled "$id" || continue
    if [ -f "$XG_STATE/conflict.$id" ]; then
      log "$id" "检测到冲突（$(cat "$XG_STATE/conflict.$id")），跳过"
      continue
    fi
    log "$id" "start @ ${1:-$STAGE}"
    feat_run "$id" start "${1:-$STAGE}"
  done
}

case "$STAGE" in
  post-fs-data|late-load|post-mount|emulated-soft-reboot)
    run_stage ;;
  service)
    run_stage service-early
    ( wait_boot; echo 0 >"$XG_STATE/boot.count"; run_stage; bb setsid sh "$XG_MODDIR/core/xguardd.sh" start ) </dev/null >/dev/null 2>&1 & ;;
  boot-completed)
    ( run_stage ) </dev/null >/dev/null 2>&1 & ;;
esac
exit 0
