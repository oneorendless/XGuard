#!/system/bin/sh
# xguard run shield allow [list|add <域名>|remove <域名>]   放行域名（误杀修复），立即重建 hosts，不联网
#   *.example.com = 放行 example.com 及其全部子域名
. "$XG_FDIR/lib.sh"
case "${1:-list}" in
  add) valid_allow "$2" || { echo "域名无效：$2"; exit 2; }; domain=$(printf '%s' "$2" | tr 'A-Z' 'a-z'); list_del "$BLOCK" "$domain"; list_add "$ALLOW" "$domain"; hosts_build || exit 1; activity_record "$domain" allowed control-panel; log $SHIELD "放行 $domain"; echo ok ;;
  remove) list_del "$ALLOW" "$2"; hosts_build; activity_record "$2" unblocked control-panel; echo ok ;;
  *) printf '{"allow":'; list_json "$ALLOW"; printf '}\n' ;;
esac
