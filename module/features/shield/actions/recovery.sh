#!/system/bin/sh
. "$XG_FDIR/lib.sh"
case "${1:-status}" in
  pause) recovery_control pause ;;
  resume) recovery_control resume ;;
  rollback) recovery_rollback ;;
  undo) domain_undo ;;
  check) health_check check ;;
  repair) health_check repair ;;
  status) recovery_json ;;
  *) exit 2 ;;
esac
