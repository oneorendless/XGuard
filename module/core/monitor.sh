#!/system/bin/sh
# XGuard passive DNS / TLS SNI observer; no iptables rules or DNS redirection.
. "$XG_MODDIR/core/lib.sh"
STATE=$XG_STATE
RUNTIME=${XGUARD_RUNTIME:-/dev/xguard}
mkdir -p "$STATE" "$RUNTIME"; chmod 0700 "$RUNTIME"
PIDFILE=$STATE/monitor.pid
SNAP=$RUNTIME/activity.json
ERR=$STATE/monitor.err
alive() {
  pid=$(cat "$PIDFILE" 2>/dev/null)
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$pid" 2>/dev/null || return 1
  case "$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null)" in *xguard-monitor*) return 0 ;; esac
  return 1
}
start() {
  alive && return 0
  [ -f "$STATE/monitor.off" ] && return 0
  [ -f "$STATE/safe_mode" ] || [ -f "$STATE/conflict.shield" ] && return 0
  feat_enabled shield || return 0
  [ ! -f "$XG_STATE/temporary-pause" ] || return 0
  abi=$(getprop ro.product.cpu.abi 2>/dev/null)
  case "$abi" in arm64-v8a|armeabi-v7a|x86|x86_64) ;; *)
    case "$(uname -m)" in aarch64) abi=arm64-v8a ;; arm*) abi=armeabi-v7a ;; x86_64) abi=x86_64 ;; i?86) abi=x86 ;; esac ;;
  esac
  binary=$XG_MODDIR/bin/$abi/xguard-monitor
  [ -x "$binary" ] || { echo "缺少 $abi 域名采集组件，请重新安装模块" >"$ERR"; return 1; }
  lock=$STATE/monitor.start.lock
  mkdir "$lock" 2>/dev/null || return 0
  trap 'rmdir "$lock" 2>/dev/null' EXIT
  alive && return 0
  feat_enabled shield && [ ! -f "$XG_STATE/temporary-pause" ] || return 0
  rm -f "$ERR" "$SNAP"
  nohup "$binary" -output "$SNAP" -hosts "$XG_DATA/shield/hosts" </dev/null >"$ERR" 2>&1 &
  echo $! >"$PIDFILE"
  n=0; while [ "$n" -lt 10 ]; do [ -s "$SNAP" ] && return 0; alive || break; sleep 0.1; n=$((n+1)); done
  [ -s "$SNAP" ] && return 0
  [ -s "$ERR" ] || echo '采集组件未就绪；请查看 Root 权限与 SELinux 日志' >"$ERR"
  return 1
}
stop() { alive && kill "$pid" 2>/dev/null; rm -f "$PIDFILE"; }
case "${1:-list}" in
  start) start; exit $? ;;
  enable) rm -f "$STATE/monitor.off"; start ;;
  disable) touch "$STATE/monitor.off"; stop ;;
  stop) stop; exit 0 ;;
  clear) : >"$SNAP.clear"; sleep 1.1 ;;
  list) start ;;
  *) exit 2 ;;
esac
running=false; alive && running=true
enabled=true; [ -f "$STATE/monitor.off" ] && enabled=false
error=$(head -c 400 "$ERR" 2>/dev/null)
printf '{"collector":{"running":%s,"enabled":%s,"error":"%s"},"snapshot":' "$running" "$enabled" "$(printf '%s' "$error" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '[:cntrl:]' ' ')"
if [ -s "$SNAP" ]; then cat "$SNAP"; else printf '{"items":[],"observed":0,"packets":0}'; fi
printf '}\n'
