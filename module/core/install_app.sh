#!/system/bin/sh
APK=$1; L=${2:-/dev/null}
cd / 2>/dev/null
STATE=${XG_STATE:-/data/adb/xguard/state}
mkdir -p "$STATE" 2>/dev/null
[ -f "$APK" ] || exit 1
SZ=$(stat -c %s "$APK" 2>/dev/null)
OUT=$(mktemp 2>/dev/null || echo /data/local/tmp/xguard-install.out)

try() { _to=$("$@" 2>&1); rc=$?; printf '%s\n' "$_to" >"$OUT"; cat "$OUT" >>"$L" 2>/dev/null; grep -q '^Success' "$OUT" && return 0; return 1; }

ok() {
  sha256sum "$APK" 2>/dev/null | cut -d' ' -f1 >"$STATE/app.sha"
  rm -f "$STATE/app_install.err" "$OUT" /data/local/tmp/xguard.apk
  [ -f "${0%/*}/legacy.sh" ] && { . "${0%/*}/legacy.sh"; legacy_retire_app; }
  exit 0
}

n=0; until pm path android </dev/null >/dev/null 2>&1; do n=$((n + 1)); [ "$n" -ge 10 ] && break; sleep 1; done

echo "[app] retry: cat | pm install -r -d -S $SZ" >>"$L"
[ -n "$SZ" ] && cat "$APK" | try pm install -r -d -S "$SZ" && ok

T=/data/local/tmp/xguard.apk
cp -f "$APK" "$T" 2>/dev/null && chmod 0644 "$T" && chcon u:object_r:shell_data_file:s0 "$T" 2>/dev/null
echo "[app] pm install -r -d (file)" >>"$L"
[ -f "$T" ] && try pm install -r -d "$T" </dev/null && ok

echo "[app] retry: install-create session" >>"$L"
_co=$(pm install-create -r -d -S "$SZ" </dev/null 2>&1); printf '%s\n' "$_co" >>"$L" 2>/dev/null
sid=$(printf '%s\n' "$_co" | sed -n 's/.*\[\([0-9]*\)\].*/\1/p')
if [ -n "$sid" ]; then
  _wo=$(cat "$APK" | pm install-write -S "$SZ" "$sid" base.apk - 2>&1); _wr=$?; printf '%s\n' "$_wo" >>"$L" 2>/dev/null
  [ "$_wr" = 0 ] && try pm install-commit "$sid" </dev/null && ok
  pm install-abandon "$sid" </dev/null >/dev/null 2>&1
fi

why=$(grep -o 'INSTALL_[A-Z_]*\|Failure \[[^]]*\]' "$OUT" 2>/dev/null | head -n1)
case "$why" in
  *UPDATE_INCOMPATIBLE*|*SIGNATURES*) msg="已装的 XGuard签名不同：请先卸载旧版 XGuard App，再开机自动补装" ;;
  *INSUFFICIENT_STORAGE*) msg="存储空间不足，清理后重启会自动补装" ;;
  *VERSION_DOWNGRADE*) msg="已装的 XGuard版本更高，系统不允许降级：卸载后重启自动补装" ;;
  *USER_RESTRICTED*|*VERIFICATION*) msg="系统拦截了安装：关闭限制后重启自动补装，或手动安装模块内 app/xguard.apk" ;;
  '') msg="系统包管理器未就绪，开机后自动补装" ;;
  *) msg="安装失败（$why），开机后自动重试" ;;
esac
echo "$msg" >"$STATE/app_install.err"
echo "[app] 失败：$msg" >>"$L"
rm -f "$OUT" "$T"
exit 1
