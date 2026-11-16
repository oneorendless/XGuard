#!/system/bin/sh
# xguard run shield block [list|add <域名>|remove <域名>]   自定义拦截域名，立即重建 hosts，不联网
. "$XG_FDIR/lib.sh"
case "${1:-list}" in
  add)
    valid_domain "${2:-}" || { echo "域名无效：${2:-}"; exit 2; }
    domain=$(printf '%s' "$2" | tr 'A-Z' 'a-z')
    grep -qixF "$domain" "$PROTECT" && { echo '该域名属于推送保护名单，无法封禁'; exit 2; }
    suffix=$domain
    while :; do
      grep -qixF "*.$suffix" "$ALLOW" 2>/dev/null && { echo "请先移除通配放行规则 *.$suffix，再封禁此域名"; exit 2; }
      case "$suffix" in *.*) suffix=${suffix#*.} ;; *) break ;; esac
    done
    list_del "$ALLOW" "$domain"
    list_add "$BLOCK" "$domain"
    hosts_build || { echo '规则构建失败，请查看日志'; exit 1; }
    grep -qxF "0.0.0.0 $domain" "$HOSTS_SRC" || { echo '域名未写入生效规则，请检查规则上限'; exit 1; }
    activity_record "$domain" blocked control-panel; log $SHIELD "自定义拦截 $domain"; echo ok ;;
  remove) list_del "$BLOCK" "$2"; hosts_build; activity_record "$2" unblocked control-panel; echo ok ;;
  *) printf '{"block":'; list_json "$BLOCK"; printf '}\n' ;;
esac
