#!/bin/sh
set -u
TASK_TMP=$(mktemp -d)
trap 'rm -rf "$TASK_TMP"' EXIT
XG_STATE=$TASK_TMP/state
XG_RUN=$TASK_TMP/run
XG_MODDIR=$TASK_TMP/module
mkdir -p "$XG_STATE" "$XG_RUN" "$XG_MODDIR"
. module/core/accessibility_guard.sh
guard=1
authorized=1
unlocked=RUNNING_UNLOCKED
current_user=0
bound=1
service_list=com.example.other/.Service
writes=0
accessibility_guard_pref() {
  case "$1" in gkd_accessibility_guard) [ "$guard" = 1 ] ;; *) [ "$authorized" = 1 ] ;; esac
}
am() { case "$1" in get-current-user) echo "$current_user" ;; *) echo "$unlocked" ;; esac; }
pm() { return 0; }
bb() { [ "$bound" = 1 ] && echo 'requested=true received=true hasBound=true' || echo 'hasBound=false'; }
settings() {
  if [ "$3" = get ]; then printf '%s' "$service_list"; return; fi
  writes=$((writes + 1))
  [ "$5" != enabled_accessibility_services ] || service_list=$6
  return 0
}
log() { :; }
sleep() { :; }
guard=0
accessibility_guard_check
[ "$writes" = 0 ] || exit 1
guard=1
authorized=0
accessibility_guard_check
[ "$writes" = 0 ] || exit 1
authorized=1
unlocked=RUNNING_LOCKED
accessibility_guard_check
[ "$writes" = 0 ] || exit 1
unlocked=RUNNING_UNLOCKED
current_user=10
accessibility_guard_check
[ "$writes" = 0 ] || exit 1
current_user=0
touch "$XG_STATE/safe_mode"
accessibility_guard_check
[ "$writes" = 0 ] || exit 1
rm "$XG_STATE/safe_mode"
accessibility_guard_check
[ "$writes" = 2 ] || exit 1
[ "$service_list" = "com.example.other/.Service:$ACCESSIBILITY_COMPONENT" ] || exit 1
bound=0
accessibility_guard_check
[ "$writes" = 2 ] || exit 1
rm "$XG_RUN/accessibility_guard.last"
accessibility_guard_check
[ "$writes" = 5 ] || exit 1
[ "$service_list" = "com.example.other/.Service:$ACCESSIBILITY_COMPONENT" ] || exit 1
bound=1
accessibility_guard_check
[ "$writes" = 5 ] || exit 1
echo 'PASS: guard opt-in, prior authorization, user/unlock/safe-mode gates, preserve other services, rebind and cooldown'
