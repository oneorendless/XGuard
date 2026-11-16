#!/system/bin/sh
# Sourced by lib.sh. No user-provided paths or shell fragments are executed.
RECOVERY=$AD_DIR/recovery
PAUSE_FILE=$XG_STATE/temporary-pause

recovery_lock() {
  recovery_lock_owned=false
  recovery_lock_dir=$XG_RUN/recovery-$1.lock
  if [ "$1" = rules ] && [ "${XGUARD_RULES_LOCKED:-}" = "$recovery_lock_dir" ]; then return 0; fi
  mkdir -p "$XG_RUN"
  _rl_wait=0
  until mkdir "$recovery_lock_dir" 2>/dev/null; do
    _rl_pid=$(cat "$recovery_lock_dir/pid" 2>/dev/null)
    case "$_rl_pid" in ''|*[!0-9]*)
      if [ $(( $(date +%s) - $(stat -c %Y "$recovery_lock_dir" 2>/dev/null || date +%s) )) -gt 30 ]; then
        rm -f "$recovery_lock_dir/pid"; rmdir "$recovery_lock_dir" 2>/dev/null; continue
      fi ;; *)
      if ! kill -0 "$_rl_pid" 2>/dev/null; then rm -f "$recovery_lock_dir/pid"; rmdir "$recovery_lock_dir" 2>/dev/null; continue; fi ;;
    esac
    _rl_wait=$((_rl_wait+1)); [ "$_rl_wait" -lt 50 ] || { echo '另一项维护操作正在进行，请稍后重试' >&2; return 1; }
    sleep 0.1
  done
  echo $$ >"$recovery_lock_dir/pid"
  recovery_lock_owned=true
  if [ "$1" = rules ]; then XGUARD_RULES_LOCKED=$recovery_lock_dir; export XGUARD_RULES_LOCKED; fi
  trap 'rm -f "$recovery_lock_dir/pid"; rmdir "$recovery_lock_dir" 2>/dev/null || :' EXIT
}

recovery_watchdog_start() {
  _wp=$(cat "$XG_RUN/recovery-watchdog.lock/pid" 2>/dev/null)
  case "$_wp" in ''|*[!0-9]*) ;; *)
    if kill -0 "$_wp" 2>/dev/null && tr '\0' ' ' <"/proc/$_wp/cmdline" 2>/dev/null | grep -q 'core/watchdog.sh'; then return 0; fi ;;
  esac
  nohup setsid sh "$XG_MODDIR/core/watchdog.sh" </dev/null >/dev/null 2>&1 &
}

pause_until() {
  _pu=$(cat "$PAUSE_FILE" 2>/dev/null)
  case "$_pu" in ''|*[!0-9]*) echo 0 ;; *) echo "$_pu" ;; esac
}
shield_paused() { [ -f "$PAUSE_FILE" ]; }
recovery_control() (
  recovery_lock control || exit 1
  case "$1" in
    pause)
      feat_enabled "$SHIELD" || { echo '请先开启防护'; exit 1; }
      recovery_watchdog_start
      _until=$(( $(date +%s) + 300 ))
      printf '%s\n' "$_until" >"$PAUSE_FILE.tmp" && mv -f "$PAUSE_FILE.tmp" "$PAUSE_FILE" || exit 1
      # Marker is written before stopping so event handlers cannot relock paths.
      XG_FEATURE=$SHIELD XG_FDIR=$XG_FDIR sh "$XG_FDIR/stop.sh" temporary >>"$XG_LOG/shield.log" 2>&1 || exit 1
      log shield '用户临时暂停防护 5 分钟'
      ;;
    resume|expire)
      [ -f "$PAUSE_FILE" ] || exit 0
      if [ "$1" = expire ] && [ "$(pause_until)" -gt "$(date +%s)" ]; then exit 0; fi
      rm -f "$PAUSE_FILE"
      # A manual disable/safe mode/conflict always wins over automatic resume.
      if feat_enabled "$SHIELD"; then
        reconcile; splash_apply
        XG_MODDIR=$XG_MODDIR sh "$XG_MODDIR/core/monitor.sh" start >/dev/null 2>&1
        shield_write_status
        log shield '临时暂停结束，已按当前开关恢复防护'
      fi ;;
    *) exit 2 ;;
  esac
)

recovery_signature() { { active_ids; custom_urls; } | cksum; }
recovery_copy_sources() {
  mkdir -p "$1" || return 1
  for _rs_file in "$SRC_DIR/"*.list "$SRC_DIR/"*.meta; do
    [ -f "$_rs_file" ] || continue
    cp -p "$_rs_file" "$1/" || return 1
  done
}
recovery_stage() {
  mkdir -p "$RECOVERY"
  recovery_stage_dir=$RECOVERY/pending.$$
  mkdir -p "$recovery_stage_dir/src" || return 1
  recovery_copy_sources "$recovery_stage_dir/src" || return 1
  if [ -f "$HOSTS_SRC" ]; then cp -p "$HOSTS_SRC" "$recovery_stage_dir/hosts" || return 1
  else : >"$recovery_stage_dir/hosts" || return 1; fi
  recovery_signature >"$recovery_stage_dir/signature"
  date +%s >"$recovery_stage_dir/time"
}
recovery_diff() {
  awk 'FILENAME==ARGV[1] {if ($1=="0.0.0.0") old[$2]=1; next}
       $1=="0.0.0.0" {if (!($2 in old)) added++; current[$2]=1}
       END {for (d in old) if (!(d in current)) removed++; printf "added=%d\nremoved=%d\n", added+0, removed+0}' "$1" "$2"
}
recovery_commit() {
  [ -s "$recovery_stage_dir/hosts" ] || { rm -rf "$recovery_stage_dir"; return 0; }
  recovery_diff "$recovery_stage_dir/hosts" "$HOSTS_SRC" >"$RECOVERY/last-update.tmp"
  printf 'time=%s\n' "$(date +%s)" >>"$RECOVERY/last-update.tmp"
  mv -f "$RECOVERY/last-update.tmp" "$RECOVERY/last-update"
  if [ "$(sed 1d "$recovery_stage_dir/hosts" | cksum)" != "$(sed 1d "$HOSTS_SRC" | cksum)" ]; then
    rm -rf "$RECOVERY/previous.old" || return 1
    [ ! -d "$RECOVERY/previous" ] || mv "$RECOVERY/previous" "$RECOVERY/previous.old" || return 1
    mv "$recovery_stage_dir" "$RECOVERY/previous" || { mv "$RECOVERY/previous.old" "$RECOVERY/previous"; return 1; }
    rm -rf "$RECOVERY/previous.old"
  else rm -rf "$recovery_stage_dir"; fi
  return 0
}

recovery_rollback() (
  recovery_lock rules || exit 1
  [ -s "$RECOVERY/previous/hosts" ] && [ -d "$RECOVERY/previous/src" ] || { echo '尚无可用的更新前快照'; exit 1; }
  [ "$(recovery_signature)" = "$(cat "$RECOVERY/previous/signature")" ] || { echo '来源选择已改变，无法安全恢复此快照；请先恢复更新时的来源选择'; exit 1; }
  # Never replace hosts' inode: netd/apps may have it bind-mounted.
  [ ! -d "$RECOVERY/restore" ] || { echo '上次恢复未完成，恢复缓存已保留；请检查存储空间与日志后处理'; exit 1; }
  mkdir -p "$RECOVERY/restore/src" || exit 1
  recovery_copy_sources "$RECOVERY/restore/src" || exit 1
  rm -f "$SRC_DIR/"*.list "$SRC_DIR/"*.meta
  for _rs_file in "$RECOVERY/previous/src/"*.list "$RECOVERY/previous/src/"*.meta; do
    [ -f "$_rs_file" ] || continue
    cp -p "$_rs_file" "$SRC_DIR/" || {
      if recovery_restore_sources "$RECOVERY/restore/src"; then rm -rf "$RECOVERY/restore"; echo '快照复制失败，原缓存已恢复'
      else echo '缓存恢复未完成，备份已保留，请检查存储空间与日志'; fi
      exit 1
    }
  done
  if ! hosts_build; then
    if recovery_restore_sources "$RECOVERY/restore/src"; then rm -rf "$RECOVERY/restore"; fi
    echo '回滚构建失败，已保留当前生效规则'; exit 1
  fi
  rm -rf "$RECOVERY/restore"
  # Prevent the next scheduled update from immediately undoing the recovery.
  echo $(( $(date +%s) + 86400 )) >"$RECOVERY/update-hold"
  meta_set result rollback
  reconcile; shield_write_status
  log shield '已回滚到更新前的源缓存；保留当前放行和封禁，自动更新暂停 24 小时'
  echo ok
)

recovery_restore_sources() {
  rm -f "$SRC_DIR/"*.list "$SRC_DIR/"*.meta
  for _restore in "$1/"*.list "$1/"*.meta; do
    [ -f "$_restore" ] || continue
    cp -p "$_restore" "$SRC_DIR/" || return 1
  done
}

domain_fingerprint() { { cat "$ALLOW" 2>/dev/null; echo '--'; cat "$BLOCK" 2>/dev/null; } | cksum; }
domain_snapshot() {
  mkdir -p "$RECOVERY/domain-pending" || return 1
  for _dk in allow block; do
    if [ -f "$AD_DIR/$_dk" ]; then cp "$AD_DIR/$_dk" "$RECOVERY/domain-pending/$_dk" || return 1
    else : >"$RECOVERY/domain-pending/$_dk" || return 1; fi
  done
}
domain_commit() {
  domain_fingerprint >"$RECOVERY/domain-pending/after" || return 1
  date +%s >"$RECOVERY/domain-pending/time" || return 1
  rm -rf "$RECOVERY/domain-undo.old" || return 1
  [ ! -d "$RECOVERY/domain-undo" ] || mv "$RECOVERY/domain-undo" "$RECOVERY/domain-undo.old" || return 1
  mv "$RECOVERY/domain-pending" "$RECOVERY/domain-undo" || { mv "$RECOVERY/domain-undo.old" "$RECOVERY/domain-undo"; return 1; }
  rm -rf "$RECOVERY/domain-undo.old"
  return 0
}
domain_restore_pending() {
  cp "$RECOVERY/domain-pending/allow" "$ALLOW" && cp "$RECOVERY/domain-pending/block" "$BLOCK" || return 1
  rm -rf "$RECOVERY/domain-pending"
}
domain_undo() (
  recovery_lock rules || exit 1
  [ -f "$RECOVERY/domain-undo/after" ] || { echo '暂无可撤销的域名操作'; exit 1; }
  [ "$(domain_fingerprint)" = "$(cat "$RECOVERY/domain-undo/after")" ] || { echo '域名名单已被其他操作修改，未撤销；请手动调整'; exit 1; }
  domain_snapshot || exit 1
  cp "$RECOVERY/domain-undo/allow" "$ALLOW" && cp "$RECOVERY/domain-undo/block" "$BLOCK" || { domain_restore_pending; exit 1; }
  hosts_build || { domain_restore_pending; exit 1; }
  rm -rf "$RECOVERY/domain-undo" "$RECOVERY/domain-pending"
  splash_network_sync; log shield '已撤销最近一次域名操作'; echo ok
)

recovery_json() {
  _backup=0; [ -f "$RECOVERY/previous/time" ] && _backup=$(cat "$RECOVERY/previous/time")
  _hold=$(cat "$RECOVERY/update-hold" 2>/dev/null); case "$_hold" in ''|*[!0-9]*) _hold=0 ;; esac
  printf '{"pause_until":%s,"backup_time":%s,"update_hold_until":%s,"undo_available":%s,"update_added":%s,"update_removed":%s,"update_time":%s,"health":' \
    "$(pause_until)" "${_backup:-0}" "$_hold" "$([ -f "$RECOVERY/domain-undo/after" ] && echo true || echo false)" \
    "$(prop_get "$RECOVERY/last-update" added 0)" "$(prop_get "$RECOVERY/last-update" removed 0)" "$(prop_get "$RECOVERY/last-update" time 0)"
  if [ -s "$RECOVERY/health.json" ]; then cat "$RECOVERY/health.json"; else printf '{}'; fi
  printf '}\n'
}

health_monitor_alive() {
  _mp=$(cat "$XG_STATE/monitor.pid" 2>/dev/null)
  case "$_mp" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$_mp" 2>/dev/null && case "$(tr '\0' ' ' <"/proc/$_mp/cmdline" 2>/dev/null)" in *xguard-monitor*) return 0 ;; esac
  return 1
}
health_check() (
  recovery_lock health || exit 1
  _desired=false; feat_enabled "$SHIELD" && _desired=true
  _paused=false; shield_paused && _paused=true
  _mount=false; hosts_mounted && _mount=true
  _monitor=false; health_monitor_alive && _monitor=true
  _collector=true; [ -f "$XG_STATE/monitor.off" ] && _collector=false
  _daemon=false; case "$(sh "$XG_MODDIR/core/xguardd.sh" status)" in running*) _daemon=true ;; esac
  _mode=$(shield_mode); _state=ok
  if [ "$_desired" = false ]; then _state=off
  elif [ "$_paused" = true ]; then _state=paused
  elif [ "$(hosts_rules)" -le 0 ]; then _state=no_rules
  elif [ "$_daemon" = false ]; then _state=daemon_stopped
  elif [ "$_mode" != proxy ] && [ "$_mount" = false ]; then _state=not_mounted
  elif [ "$_collector" = true ] && [ "$_monitor" = false ]; then _state=collector_stopped; fi
  _action=none
  if [ "${1:-check}" != check ] && [ "$_desired" = true ] && [ "$_paused" = false ]; then
    recovery_watchdog_start
    if [ "$_daemon" = false ]; then
      nohup setsid sh "$XG_MODDIR/core/xguardd.sh" start </dev/null >/dev/null 2>&1 &
      _action=repair
      sleep 0.3
    fi
    if [ "$_state" != no_rules ] && { [ "$_mode" != proxy ] && [ "$_mount" = false ]; }; then reconcile; _action=repair; fi
    if [ "$_collector" = true ] && [ "$_monitor" = false ]; then sh "$XG_MODDIR/core/monitor.sh" start >/dev/null 2>&1; _action=repair; fi
    _mount=false; hosts_mounted && _mount=true
    _monitor=false; health_monitor_alive && _monitor=true
    _daemon=false; case "$(sh "$XG_MODDIR/core/xguardd.sh" status)" in running*) _daemon=true ;; esac
    _state=ok
    if [ "$(hosts_rules)" -le 0 ]; then _state=no_rules
    elif [ "$_daemon" = false ]; then _state=daemon_stopped
    elif [ "$_mode" != proxy ] && [ "$_mount" = false ]; then _state=not_mounted
    elif [ "$_collector" = true ] && [ "$_monitor" = false ]; then _state=collector_stopped; fi
    [ "$_action" = none ] || log shield "健康维护：$_action，检查结果 $_state"
  fi
  mkdir -p "$RECOVERY"
  printf '{"state":"%s","checked_at":%s,"desired":%s,"paused":%s,"hosts_mounted":%s,"daemon_running":%s,"collector_running":%s,"collector_enabled":%s,"mode":"%s","action":"%s"}\n' \
    "$_state" "$(date +%s)" "$_desired" "$_paused" "$_mount" "$_daemon" "$_monitor" "$_collector" "$_mode" "$_action" >"$RECOVERY/health.tmp"
  mv "$RECOVERY/health.tmp" "$RECOVERY/health.json"
  cat "$RECOVERY/health.json"
)
