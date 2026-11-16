#!/system/bin/sh
# $1 = 事件  $2 = 参数
. "$XG_FDIR/lib.sh"
case "$1" in
  net) sleep 3; reconcile                    # 代理服务启停通常伴随路由变化
       src_missing && shield_kick_update net ;;  # 联网了但还有源从没下载成功（首次安装 / 开机时没网）
  tick) hosts_update; reconcile; splash_apply ;;
  splash) splash_apply ;;
  config)
    case "$2" in
      shield/config.json|adblock.prop) reconcile; splash_apply ;;   # 本插件配置变了
      *) splash_apply ;;
    esac ;;
esac
# 刷新契约状态文件（xguardd 只转发 config.json 变化，写 status.json 不会自激）
shield_write_status
exit 0
