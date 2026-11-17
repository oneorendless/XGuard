#!/system/bin/sh
ACCESSIBILITY_COMPONENT=com.xuan.xguard/com.xuan.xguard.XGuardAccessibilityService
ACCESSIBILITY_SHORT=com.xuan.xguard/.XGuardAccessibilityService

accessibility_guard_pref() {
  grep -q "name=\"$1\" value=\"true\"" /data/user/0/com.xuan.xguard/shared_prefs/xguard.xml 2>/dev/null
}

accessibility_guard_services() {
  _a11y_services=$(settings --user 0 get secure enabled_accessibility_services 2>/dev/null) || return 1
  case "$_a11y_services" in null) _a11y_services= ;; esac
}

accessibility_guard_without_self() {
  printf '%s' "$_a11y_services" | tr ':' '\n' | awk -v full="$ACCESSIBILITY_COMPONENT" -v short="$ACCESSIBILITY_SHORT" '
    length($0) && $0 != full && $0 != short { if (count++) printf ":"; printf "%s", $0 }
  '
}

accessibility_guard_check() {
  [ -f "$XG_STATE/safe_mode" ] && return 0
  [ -f "$XG_MODDIR/disable" ] && return 0
  [ -f "$XG_MODDIR/remove" ] && return 0
  accessibility_guard_pref gkd_accessibility_guard || return 0
  accessibility_guard_pref gkd_accessibility_ever_connected || return 0
  [ "$(am get-current-user 2>/dev/null)" = 0 ] || return 0
  [ "$(am get-started-user-state 0 2>/dev/null)" = RUNNING_UNLOCKED ] || return 0
  pm path com.xuan.xguard >/dev/null 2>&1 || return 0
  accessibility_guard_services || return 0
  _a11y_enabled=0
  case ":$_a11y_services:" in *":$ACCESSIBILITY_COMPONENT:"*|*":$ACCESSIBILITY_SHORT:"*) _a11y_enabled=1 ;; esac
  if [ "$_a11y_enabled" = 1 ]; then
    _a11y_binding=$(bb timeout 5 dumpsys activity services "$ACCESSIBILITY_SHORT" 2>/dev/null) || return 0
    case "$_a11y_binding" in *hasBound=true*) return 0 ;; esac
  fi
  _a11y_now=$(date +%s)
  _a11y_previous=$(cat "$XG_RUN/accessibility_guard.last" 2>/dev/null)
  case "$_a11y_previous" in ''|*[!0-9]*) _a11y_previous=0 ;; esac
  [ $((_a11y_now - _a11y_previous)) -lt 300 ] && return 0
  printf '%s\n' "$_a11y_now" >"$XG_RUN/accessibility_guard.last"
  if [ "$_a11y_enabled" = 1 ]; then
    accessibility_guard_services || return 0
    settings --user 0 put secure enabled_accessibility_services "$(accessibility_guard_without_self)" >/dev/null 2>&1 || return 0
    sleep 1
  fi
  accessibility_guard_pref gkd_accessibility_guard || return 0
  accessibility_guard_services || return 0
  _a11y_others=$(accessibility_guard_without_self)
  settings --user 0 put secure enabled_accessibility_services "${_a11y_others:+$_a11y_others:}$ACCESSIBILITY_COMPONENT" >/dev/null 2>&1 || return 0
  settings --user 0 put secure accessibility_enabled 1 >/dev/null 2>&1
  log watchdog "无障碍守护已请求重新绑定 XGuard，保留其他服务"
}
