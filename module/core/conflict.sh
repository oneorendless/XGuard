#!/system/bin/sh
. "$XG_MODDIR/core/lib.sh"

module_active() {   # 已安装且未禁用、未待删除；套件自己建的兼容垫片不算
  [ -f "/data/adb/modules/$1/.xguard-shim" ] && return 1
  grep -q '^version=suite$' "/data/adb/modules/$1/module.prop" 2>/dev/null && return 1
  [ -d "/data/adb/modules/$1" ] && [ ! -f "/data/adb/modules/$1/disable" ] && [ ! -f "/data/adb/modules/$1/remove" ]
}

module_name() { prop_get "/data/adb/modules/$1/module.prop" name "$1"; }

rm -f "$XG_STATE"/conflict.* 2>/dev/null
for id in $(feat_list); do
  hits=""; why=""
  for m in $(legacy_conflict_ids) $(feat_meta "$id" conflicts | tr ',' ' '); do
    if module_active "$m"; then
      hits="$hits $m"
      why="${why:+$why；}已启用模块「$(module_name "$m")」($m)，与$(feat_meta "$id" name "$id")做同类事，同时运行会互相覆盖"
    fi
  done
  if [ -f "$XG_FEATURES/$id/conflict.sh" ]; then
    extra=$(XG_FDIR=$XG_FEATURES/$id sh "$XG_FEATURES/$id/conflict.sh" 2>/dev/null)
    if [ -n "$extra" ]; then
      hits="$hits $(printf '%s\n' "$extra" | head -n1)"
      r=$(printf '%s\n' "$extra" | sed -n '2,$p' | tr '\n' ' ')
      why="${why:+$why；}${r:-检测到 $(printf '%s\n' "$extra" | head -n1)}"
    fi
  fi
  if [ -n "$hits" ]; then
    echo "${hits# }" >"$XG_STATE/conflict.$id"
    printf '%s\n' "$why" >"$XG_STATE/conflict.$id.why"
    log conflict "$id ←$hits（$why）"
  fi
done
exit 0
