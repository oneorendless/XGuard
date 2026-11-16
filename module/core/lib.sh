#!/system/bin/sh
. "$XG_MODDIR/core/env.sh"

core_init_dirs() {
  mkdir -p "$XG_CFG" "$XG_STATE" "$XG_LOG" "$XG_RUN"
  chmod 0700 "$XG_DATA"
}

log_rotate() {
  [ -f "$1" ] || return 0
  [ "$(wc -c <"$1" 2>/dev/null || echo 0)" -gt 524288 ] || return 0
  mv -f "$1.1" "$1.2" 2>/dev/null; mv -f "$1" "$1.1"
}
log() {
  _t=$1; shift
  _f=$XG_LOG/core.log
  log_rotate "$_f"
  printf '%s [%s] %s\n' "$(date '+%m-%d %H:%M:%S')" "$_t" "$*" >>"$_f"
}

prop_get() {
  _v=$(sed -n "s/^$2=//p" "$1" 2>/dev/null | tail -n1 | sed 's/[[:space:]]\{1,\}#.*$//; s/[[:space:]]*$//')
  [ -n "$_v" ] && printf '%s' "$_v" || printf '%s' "${3:-}"
}
prop_set() {
  _tmp=$1.tmp.$$
  { grep -v "^$2=" "$1" 2>/dev/null; printf '%s=%s\n' "$2" "$3"; } >"$_tmp" && mv -f "$_tmp" "$1"
}
settings_get() { prop_get "$XG_CFG/settings.prop" "$1" "${2:-}"; }
settings_set() { prop_set "$XG_CFG/settings.prop" "$1" "$2"; }
. "$XG_MODDIR/core/config.sh"
. "$XG_MODDIR/core/legacy.sh"
feat_cfg_get() { core_cfg_get "$1" "$2" "${3:-}"; }

feat_list() {
  for _d in "$XG_FEATURES"/*/; do
    _id=$(basename "$_d")
    case "$_id" in _*) continue ;; esac
    [ -f "$_d/feature.prop" ] && echo "$_id"
  done
}
feat_meta() { prop_get "$XG_FEATURES/$1/feature.prop" "$2" "${3:-}"; }

feat_enabled() {
  [ -f "$XG_STATE/safe_mode" ] && return 1
  [ -f "$XG_STATE/conflict.$1" ] && return 1
  [ -f "$XG_STATE/paused.$1" ] && return 1
  [ -f "$XG_STATE/brick.$1" ] && return 1
  _e=$(settings_get "feature.$1.enabled")
  [ -z "$_e" ] && _e=$(feat_meta "$1" default_enabled 0)
  [ "$_e" = 1 ]
}

feat_for_stage_scan() {
  for _id in $(feat_list); do
    case " $(feat_meta "$_id" stages) " in *" $1 "*)
      printf '%s %s\n' "$(feat_meta "$_id" order 50)" "$_id" ;; esac
  done | sort -n | awk '{print $2}'
}
feat_for_stage() {
  _kc=$XG_STATE/stages.cache
  _ksig=$(cat "$XG_FEATURES"/*/feature.prop 2>/dev/null | cksum)
  if [ -f "$_kc" ]; then
    _kfirst=1; _khit=0
    while IFS= read -r _kl; do
      if [ $_kfirst = 1 ]; then _kfirst=0; [ "$_kl" = "sig=$_ksig" ] || break; _khit=1; continue; fi
      case "$_kl" in "$1:"*) _kids=${_kl#*:}; for _kid in $_kids; do echo "$_kid"; done; return 0 ;; esac
    done <"$_kc"
    [ $_khit = 1 ] && case " post-fs-data late-load post-mount service-early service boot-completed emulated-soft-reboot " in *" $1 "*) return 0 ;; esac
  fi
  { echo "sig=$_ksig"
    for _kst in post-fs-data late-load post-mount service-early service boot-completed emulated-soft-reboot; do
      echo "$_kst:" $(feat_for_stage_scan "$_kst")
    done; } >"$_kc.tmp.$$" 2>/dev/null && mv -f "$_kc.tmp.$$" "$_kc" 2>/dev/null
  case " post-fs-data late-load post-mount service-early service boot-completed emulated-soft-reboot " in
    *" $1 "*) sed -n "s/^$1: *//p" "$_kc" 2>/dev/null | tr ' ' '\n' | sed '/^$/d' ;;
    *) feat_for_stage_scan "$1" ;;
  esac
}

feat_for_event() {
  for _id in $(feat_list); do
    feat_enabled "$_id" || continue
    case ",$(feat_meta "$_id" events)," in *",$1,"*) echo "$_id" ;; esac
  done
}

feat_run() {
  _id=$1; _act=$2; shift 2
  _sh=$XG_FEATURES/$_id/$_act.sh
  [ -f "$_sh" ] || return 0
  _to=$(feat_meta "$_id" timeout 60)
  if [ "$_act" = start ]; then
    case "${1:-}" in post-fs-data|late-load)
      _te=$(feat_meta "$_id" timeout_early ""); case "$_te" in ''|*[!0-9]*) ;; *) _to=$_te ;; esac ;;
    esac
  fi
  log_rotate "$XG_LOG/$_id.log"
  XG_FEATURE=$_id XG_FDIR=$XG_FEATURES/$_id \
    bb timeout "$_to" sh "$_sh" "$@" >>"$XG_LOG/$_id.log" 2>&1
  _rc=$?
  feat_health "$_id" "$_act" "$_rc"
  return $_rc
}

feat_health() {
  case "$2" in stop|status) return 0 ;; esac
  _hf=$XG_STATE/fail.$1
  if [ "$3" -eq 0 ] 2>/dev/null; then rm -f "$_hf"; return 0; fi
  if [ "$3" -lt 124 ] 2>/dev/null; then log "$1" "$2 失败 rc=$3"; return 0; fi
  _hn=$(cat "$_hf" 2>/dev/null); case "$_hn" in ''|*[!0-9]*) _hn=0 ;; esac
  _hn=$((_hn + 1)); echo "$_hn" >"$_hf"
  case "$3" in 124|143) _hw="$2 超时" ;; *) _hw="$2 失败 rc=$3" ;; esac
  log "$1" "$_hw（连续第 $_hn 次）"
  if [ "$_hn" -ge "$(settings_get core.fail_max 3)" ] && [ ! -f "$XG_STATE/paused.$1" ]; then
    echo "连续 $_hn 次 $_hw，已自动暂停" >"$XG_STATE/paused.$1"
    log core "暂停插件 $1：连续 $_hn 次 $_hw"
    XG_FEATURE=$1 XG_FDIR=$XG_FEATURES/$1 bb timeout 20 sh "$XG_FEATURES/$1/stop.sh" paused >>"$XG_LOG/$1.log" 2>&1
  fi
}

feat_clear_health() { rm -f "$XG_STATE/paused.$1" "$XG_STATE/brick.$1" "$XG_STATE/fail.$1"; }

feat_health_state() {
  if [ -f "$XG_STATE/brick.$1" ]; then printf 'brick:%s' "$(head -n1 "$XG_STATE/brick.$1")"
  elif [ -f "$XG_STATE/paused.$1" ]; then printf 'paused:%s' "$(head -n1 "$XG_STATE/paused.$1")"
  else printf ok; fi
}

core_track_changes() {
  _kall=$( { cat "$XG_FEATURES"/*/feature.prop "$XG_CFG"/*.prop "$XG_DATA"/*/config.json; \
             ls -l "$XG_FEATURES"/*/ ; } 2>/dev/null | cksum)
  [ "$(cat "$XG_STATE/fp.all" 2>/dev/null)" = "$_kall" ] && return 0
  echo "$_kall" >"$XG_STATE/fp.all"
  for _id in $(feat_list); do
    _fp=$( { cat "$XG_FEATURES/$_id/feature.prop"; ls -l "$XG_FEATURES/$_id" 2>/dev/null | awk '{print $5,$NF}'; \
            cat "$XG_CFG/$_id.prop" "$XG_DATA/$_id/config.json" 2>/dev/null; settings_get "feature.$_id.enabled"; } 2>/dev/null | cksum | cut -d' ' -f1)
    if [ "$(cat "$XG_STATE/fp.$_id" 2>/dev/null)" != "$_fp" ]; then
      echo "$_fp" >"$XG_STATE/fp.$_id"; date +%s >"$XG_STATE/changed.$_id"
    fi
  done
}

core_blame_candidate() {
  for _id in $(feat_list); do
    feat_enabled "$_id" || continue
    printf '%s %s\n' "$(cat "$XG_STATE/changed.$_id" 2>/dev/null || echo 0)" "$_id"
  done | sort -rn | awk 'NR==1{print $2}'
}

lock_try() { mkdir "$XG_RUN/$1.lock" 2>/dev/null; }
lock_free() { rmdir "$XG_RUN/$1.lock" 2>/dev/null; }

wait_boot() {
  _n=0
  while [ "$(getprop sys.boot_completed)" != 1 ] && [ $_n -lt 180 ]; do sleep 1; _n=$((_n+1)); done
}

core_emit() {
  case "$1" in ''|*[!a-z0-9._-]*) log core "拒绝非法事件名：$1"; return 1 ;; esac
  _ev=$1; _arg=${2:-}
  log core "事件 $_ev $_arg（来自 ${XG_FEATURE:-?}）"
  if [ -p "$XG_RUN/events" ] && [ -f "$XG_RUN/xguardd.pid" ] && kill -0 "$(cat "$XG_RUN/xguardd.pid")" 2>/dev/null; then
    echo "$_ev $_arg" >"$XG_RUN/events"
  else
    for _sid in $(feat_for_event "$_ev"); do
      [ "$_sid" = "${XG_FEATURE:-}" ] && continue
      ( feat_run "$_sid" on_event "$_ev" "$_arg" ) >/dev/null 2>&1 &
    done
  fi
}
