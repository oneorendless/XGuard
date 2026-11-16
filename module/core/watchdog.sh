#!/system/bin/sh
XG_MODDIR=$(cd "${0%/*}/.." && pwd); export XG_MODDIR
XG_FDIR=$XG_MODDIR/features/shield; export XG_FDIR
. "$XG_FDIR/lib.sh"
recovery_lock watchdog || exit 0
while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 15; done
while :; do
  if shield_paused && [ "$(pause_until)" -le "$(date +%s)" ]; then recovery_control expire; fi
  if feat_enabled shield && ! shield_paused; then
    _checked=$(core_json_get "$RECOVERY/health.json" checked_at)
    case "$_checked" in ''|*[!0-9]*) _checked=0 ;; esac
    if [ $(( $(date +%s) - _checked )) -ge 120 ]; then health_check auto >/dev/null 2>&1; fi
  fi
  sleep 15
done
