#!/system/bin/sh
. "$XG_FDIR/lib.sh"
for pkg in "$@"; do
  case "$pkg" in *[!A-Za-z0-9_.]*) echo '无效包名'; exit 2 ;; esac
  valid_pkg "$pkg" || { echo '无效包名'; exit 2; }
done
splash_mutex || exit 1
next=$APP_ALLOW.next
previous=$APP_ALLOW.previous
: >"$next" || exit 1
if [ "$#" -gt 0 ]; then printf '%s\n' "$@" | sort -u >"$next" || exit 1; fi
if [ -s "$APP_ALLOW" ] || [ -s "$next" ]; then
  if ! cmp -s "$APP_ALLOW" "$next"; then
    if [ -f "$APP_ALLOW" ]; then cp "$APP_ALLOW" "$previous" || exit 1; else : >"$previous" || exit 1; fi
    mv -f "$next" "$APP_ALLOW" || exit 1
    if ! guard_sync; then
      mv -f "$previous" "$APP_ALLOW"
      guard_sync >/dev/null 2>&1
      echo '无法同步 HTTPDNS 应用白名单'
      exit 1
    fi
    failed=0
    unlocked=
    while IFS= read -r pkg; do
      grep -Fxq "$pkg" "$previous" && continue
      if splash_unlock_targets "$pkg"; then unlocked="$unlocked $pkg"
      else failed=1; fi
    done <"$APP_ALLOW"
    if [ "$failed" = 1 ]; then
      mv -f "$previous" "$APP_ALLOW"
      guard_sync >/dev/null 2>&1
      for pkg in $unlocked; do splash_apply_locked "$pkg"; done
      echo '无法解锁该应用的开屏缓存'
      exit 1
    fi
    while IFS= read -r pkg; do
      app_allowlisted "$pkg" || splash_apply_locked "$pkg"
    done <"$previous"
    splash_network_sync
    log shield '已同步应用白名单（系统 hosts 继续生效）'
  fi
fi
rm -f "$next" "$previous"
echo ok
