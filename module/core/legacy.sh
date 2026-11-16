#!/system/bin/sh
# Previous-format identifiers exist only in this compatibility boundary.
# Never rewrite or delete the user's original data directories.
legacy_conflict_ids() { echo xiguli_suite; }
legacy_proxy_active() {
  [ -f /data/adb/hetu/running ] || return 1
  _legacy_proxy_pid=$(head -n1 /data/adb/hetu/running 2>/dev/null | tr -cd '0-9')
  [ -z "$_legacy_proxy_pid" ] && return 0
  kill -0 "$_legacy_proxy_pid" 2>/dev/null
}
legacy_import_data() {
  _legacy_root=$1
  [ -d "$_legacy_root" ] || return 0
  mkdir -p "$XG_DATA/shield" "$XG_CFG" "$XG_STATE"
  for _legacy_id in xiezhi adblock; do
    for _legacy_item in config.json allow block splash.rules skip hosts.meta; do
      [ -f "$_legacy_root/$_legacy_id/$_legacy_item" ] || continue
      [ -e "$XG_DATA/shield/$_legacy_item" ] || cp -p "$_legacy_root/$_legacy_id/$_legacy_item" "$XG_DATA/shield/$_legacy_item" || return 1
    done
    if [ -d "$_legacy_root/$_legacy_id/src" ] && [ ! -e "$XG_DATA/shield/src" ]; then
      cp -a "$_legacy_root/$_legacy_id/src" "$XG_DATA/shield/src" || return 1
    fi
    core_prop_to_json "$_legacy_root/config/$_legacy_id.prop" shield
    for _legacy_list in allow block splash.rules skip; do
      [ -f "$_legacy_root/config/$_legacy_id.$_legacy_list" ] || continue
      [ -e "$XG_DATA/shield/$_legacy_list" ] || cp -p "$_legacy_root/config/$_legacy_id.$_legacy_list" "$XG_DATA/shield/$_legacy_list" || return 1
    done
    if [ -z "$(settings_get feature.shield.enabled)" ]; then
      _legacy_enabled=$(prop_get "$_legacy_root/config/suite.prop" "feature.$_legacy_id.enabled")
      case "$_legacy_enabled" in 0|1) settings_set feature.shield.enabled "$_legacy_enabled" ;; esac
    fi
  done
  for _legacy_flag in monitor.off safe_mode; do
    [ -f "$_legacy_root/state/$_legacy_flag" ] && touch "$XG_STATE/$_legacy_flag"
  done
  for _legacy_key in yield process; do
    _legacy_value=$(core_json_get "$XG_DATA/shield/config.json" "hetu_$_legacy_key" || true)
    if [ -n "$_legacy_value" ] && ! core_json_get "$XG_DATA/shield/config.json" "proxy_$_legacy_key" >/dev/null; then
      core_json_set "$XG_DATA/shield/config.json" "proxy_$_legacy_key" "$_legacy_value" || return 1
    fi
    core_json_del "$XG_DATA/shield/config.json" "hetu_$_legacy_key"
  done
  return 0
}
legacy_migrate_data() {
  [ -f "$XG_STATE/migration.v080" ] && return 0
  if [ -d /data/adb/xiezhi ]; then legacy_import_data /data/adb/xiezhi || return 1
  else legacy_import_data /data/adb/xiguli_suite || return 1; fi
  date +%s >"$XG_STATE/migration.v080"
}
legacy_retire_module() {
  _legacy_module=/data/adb/modules/xiezhi
  [ -f "$_legacy_module/module.prop" ] || return 0
  # Unmount using its own implementation before the new namespace starts.
  XGL_MODDIR=$_legacy_module sh "$_legacy_module/system/bin/xgl" disable xiezhi >>"$INSTALL_LOG" 2>&1
  XGL_MODDIR=$_legacy_module sh "$_legacy_module/system/bin/xgl" daemon stop >>"$INSTALL_LOG" 2>&1
  XGL_MODDIR=$_legacy_module sh "$_legacy_module/kunlun/monitor.sh" stop >>"$INSTALL_LOG" 2>&1
  touch "$_legacy_module/disable"
}
legacy_retire_app() {
  # Install the new package first. Retain old App data for rollback.
  pm path com.xuan.xguard >/dev/null 2>&1 || return 0
  pm path com.xiezhi.guard >/dev/null 2>&1 && pm disable-user --user 0 com.xiezhi.guard >/dev/null 2>&1
  return 0
}
