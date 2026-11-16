#!/system/bin/sh
# xguard run shield rules                         内置 + 自定义开屏规则（JSON）
# xguard run shield rules add <包名> <目录>        新增自定义规则（目录相对 /data/data/<包>/，@sdcard: 前缀为 Android/data）
# xguard run shield rules remove <包名> <目录>     删除自定义规则并解锁这一条
. "$XG_FDIR/lib.sh"
case "${1:-}" in
  add) rule_add "$2" "$3" && echo ok ;;
  remove) rule_remove "$2" "$3" && echo ok ;;
  *) rules_json ;;
esac
