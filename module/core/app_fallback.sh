#!/system/bin/sh
MODDIR=${1:-${0%/*}/..}
D=/data/adb/xguard
ST=$D/state; L=$D/logs/install.log
APK=$MODDIR/app/xguard.apk
PKG=com.xuan.xguard
cd / 2>/dev/null
[ -f "$APK" ] || exit 0
mkdir -p "$ST" "$D/logs" 2>/dev/null

if [ "$2" = wait ]; then
  n=0; while [ "$(getprop sys.boot_completed)" != 1 ] && [ $n -lt 150 ]; do sleep 2; n=$((n + 1)); done
fi

bid=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
[ -n "$bid" ] && [ "$(cat "$ST/app_fallback.boot" 2>/dev/null)" = "$bid" ] && exit 0
[ -n "$bid" ] && echo "$bid" >"$ST/app_fallback.boot"

want=$(sed -n 's/^versionCode=//p' "$MODDIR/module.prop" | head -n 1)
have=$(pm list packages --show-versioncode "$PKG" </dev/null 2>/dev/null | sed -n "s/^package:$PKG versionCode:\([0-9]*\).*/\1/p" | head -n 1)
[ -n "$have" ] || have=$(dumpsys package "$PKG" </dev/null 2>/dev/null | sed -n 's/.*versionCode=\([0-9]*\).*/\1/p' | head -n 1)
sha=$(sha256sum "$APK" 2>/dev/null | cut -d' ' -f1)
last=$(cat "$ST/app.sha" 2>/dev/null)
if [ -n "$have" ] && [ "${have:-0}" -ge "${want:-0}" ] 2>/dev/null && [ "$sha" = "$last" ]; then exit 0; fi

if [ -z "$have" ]; then why="未安装"
elif [ "$have" -lt "${want:-0}" ] 2>/dev/null; then why="版本落后"
else why="安装包指纹不同"; fi
echo "[boot] $(date '+%m-%d %T') app ${have:-无} -> $want（$why），开机补装" >>"$L" 2>/dev/null
for i in 1 2 3; do
  if XG_STATE=$ST sh "$MODDIR/core/install_app.sh" "$APK" "$L"; then
    touch "$ST/app_install.done"
    echo "[boot] 补装成功（第 $i 次）" >>"$L" 2>/dev/null
    exit 0
  fi
  echo "[boot] 补装第 $i 次失败：$(cat "$ST/app_install.err" 2>/dev/null)" >>"$L" 2>/dev/null
  [ $i -lt 3 ] && sleep 20
done
exit 1
