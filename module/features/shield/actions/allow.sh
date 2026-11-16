#!/system/bin/sh
# xguard run shield allow [list|add <域名>|remove <域名>]   放行域名（误杀修复），立即重建 hosts，不联网
#   *.example.com = 放行 example.com 及其全部子域名
. "$XG_FDIR/lib.sh"
case "${1:-list}" in
  add|remove)
    valid_allow "${2:-}" || { echo '域名无效'; exit 2; }
    domain=$(printf '%s' "$2" | tr 'A-Z' 'a-z')
    recovery_lock rules || exit 1
    domain_snapshot || exit 1
    if [ "$1" = add ]; then list_del "$BLOCK" "$domain"; list_add "$ALLOW" "$domain"
    else list_del "$ALLOW" "$domain"; fi
    hosts_build || { domain_restore_pending; echo '构建失败，原名单已保留'; exit 1; }
    domain_commit || { domain_restore_pending; hosts_build; exit 1; }
    splash_network_sync
    activity_record "$domain" "$([ "$1" = add ] && echo allowed || echo unblocked)" control-panel
    log "$SHIELD" "放行名单 $1 $domain"; echo ok; exit 0 ;;
esac
case "${1:-list}" in
  *) printf '{"allow":'; list_json "$ALLOW"; printf '}\n' ;;
esac
