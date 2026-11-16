#!/system/bin/sh
# xguard run shield sources                        规则源（JSON）：sources=生效中的地址（兼容旧 WebUI）、list=明细（内置目录 + 自定义）
# xguard run shield sources enable|disable <id>    开关内置源（id 见 features/shield/sources.list），立即用缓存重建；没缓存的源下次更新时下载
# xguard run shield sources add <url>              追加自定义源（http/https，不联网，下次更新生效）
# xguard run shield sources remove <url|id>        删除自定义源；给的是内置源地址 / id 则关闭该源
# xguard run shield sources reset                  恢复默认（默认开的内置源，清空自定义源）
# xguard run shield sources interval <小时>        自动更新间隔，0=只手动，最大 720
. "$XG_FDIR/lib.sh"
case "${1:-}" in enable|disable|add|remove|reset|interval) recovery_lock rules || exit 1 ;; esac
valid_url() { printf '%s' "$1" | grep -qE '^https?://[A-Za-z0-9._~:/?#@!$&()*+,;=%-]+$' && [ ${#1} -le 512 ]; }
known_id() { cat_ids | grep -qx "$1"; }
set_ids() { core_cfg_set $SHIELD sources "$1"; hosts_build; }
id_of_url() { cat_lines | awk -F'|' -v u="$1" '{n=split($5,a," "); for(i=1;i<=n;i++) if (a[i]==u) {print $1; exit}}'; }
case "${1:-}" in
  enable|disable)
    known_id "${2:-}" || { echo "未知规则源：${2:-}"; exit 2; }
    n=""; for i in $(src_enabled_ids); do [ "$i" = "$2" ] || n="$n $i"; done
    [ "$1" = enable ] && n="$n $2"
    # 按目录顺序存
    o=""; for i in $(cat_ids); do case " $n " in *" $i "*) o="$o $i" ;; esac; done; o=${o# }
    [ -n "$o$(custom_urls)" ] || { echo "至少保留一个规则源"; exit 2; }
    set_ids "$o"; log $SHIELD "规则源 $2 → $1"
    if [ "$1" = enable ] && ! is_builtin "$2" && [ ! -s "$SRC_DIR/$2.list" ]; then echo "ok need_update"; else echo ok; fi ;;
  add) valid_url "$2" || { echo "地址无效：$2（需 http/https，不能含空格或引号）"; exit 2; }
       id=$(id_of_url "$2"); [ -n "$id" ] && { sh "$0" enable "$id"; exit; }
       cur=$(custom_urls | tr '\n' ' ')
       case " $cur " in *" $2 "*) echo "已存在"; exit 0 ;; esac
       core_cfg_set $SHIELD hosts_url "${cur% } $2"; log $SHIELD "新增自定义规则源 $2"; echo ok ;;
  remove)
       id=$2; known_id "$id" || id=$(id_of_url "$2")
       if [ -n "$id" ]; then sh "$0" disable "$id"; exit; fi
       n=""; for u in $(custom_urls); do [ "$u" = "$2" ] || [ "$(custom_id "$u")" = "$2" ] || n="$n $u"; done
       [ -n "${n# }$(src_enabled_ids)" ] || { echo "至少保留一个规则源"; exit 2; }
       core_cfg_set $SHIELD hosts_url "${n# }"; rm -f "$SRC_DIR/$(custom_id "$2").list" "$SRC_DIR/$(custom_id "$2").meta"
       hosts_build; log $SHIELD "删除自定义规则源 $2"; echo ok ;;
  reset) core_cfg_set $SHIELD sources "$(cat_default_ids)"; core_cfg_set $SHIELD hosts_url ""; hosts_build; echo ok ;;
  interval) case "$2" in ''|*[!0-9]*) echo "间隔需为 0~720 的整数"; exit 2 ;; esac
       [ "$2" -le 720 ] || { echo "间隔需为 0~720 的整数"; exit 2; }
       core_cfg_set $SHIELD hosts_interval_h "$2"; echo ok ;;
  *) printf '{"sources":['; f=1
     for i in $(active_ids); do
       is_builtin "$i" && continue
       case "$i" in custom_*) u=$(for c in $(custom_urls); do [ "$(custom_id "$c")" = "$i" ] && echo "$c"; done) ;; *) u=$(cat_field "$i" 5 | cut -d' ' -f1) ;; esac
       [ $f = 1 ] || printf ','; f=0; printf '"%s"' "$(json_esc "$u")"
     done
     printf '],"interval_h":%s,"sources_ok":%s,"list":' "$(core_cfg_get $SHIELD hosts_interval_h 24)" "$(prop_get "$META" sources_ok 0)"
     sources_json; printf '}\n' ;;
esac
