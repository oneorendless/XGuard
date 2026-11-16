#!/system/bin/sh
SKIPUNZIP=0
XG_MODDIR=$MODPATH; export XG_MODDIR
. "$MODPATH/core/lib.sh"
core_init_dirs
INSTALL_LOG=$XG_LOG/install.log
: >"$INSTALL_LOG"
[ "$API" -ge 30 ] || abort '! 需要 Android 11 及以上'
ui_print ' '
ui_print "  XGuard $(prop_get "$MODPATH/module.prop" version)"
ui_print '  网络防护 · Xuan'
for _script in "$MODPATH"/*.sh "$MODPATH"/core/*.sh "$MODPATH"/features/shield/*.sh "$MODPATH"/features/shield/actions/*.sh; do
  sh -n "$_script" 2>>"$INSTALL_LOG" || abort "! 脚本校验失败：${_script##*/}"
done
legacy_migrate_data || abort '! 配置迁移失败，原数据已保留，请查看安装日志'
legacy_retire_module
[ -f "$XG_CFG/settings.prop" ] || echo 'feature.shield.enabled=1' >"$XG_CFG/settings.prop"
echo 0 >"$XG_STATE/boot.count"
if [ -f "$MODPATH/app/xguard.apk" ]; then
  _pending=/data/local/tmp/xguard-pending
  mkdir -p "$_pending"
  cp -f "$MODPATH/app/xguard.apk" "$_pending/xguard.apk"
  cp -f "$MODPATH/core/install_app.sh" "$MODPATH/core/legacy.sh" "$_pending/"
  ( cd / && setsid sh -c 'export XG_STATE=/data/adb/xguard/state; for i in 1 2 3 4 5; do sh /data/local/tmp/xguard-pending/install_app.sh /data/local/tmp/xguard-pending/xguard.apk /data/adb/xguard/logs/install.log && break; sleep 5; done' </dev/null >/dev/null 2>&1 & )
fi
set_perm_recursive "$MODPATH" 0 0 0755 0644
find "$MODPATH/bin" -type f -name xguard-monitor -exec chmod 0755 {} +
find "$MODPATH" -type f -name '*.sh' -exec chmod 0755 {} +
set_perm "$MODPATH/system/bin/xguard" 0 2000 0755
ui_print '  ✓ 规则与设置已迁移，原数据保留'
ui_print '  ✓ XGuard 0.8.3 App / WebUI'
ui_print '  重启后生效 · 新 App 首次打开需授予 Root'
