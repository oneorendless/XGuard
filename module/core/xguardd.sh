#!/system/bin/sh
XG_MODDIR=$(cd "${0%/*}/.." && pwd); export XG_MODDIR
. "$XG_MODDIR/core/lib.sh"
core_init_dirs
PIDF=$XG_RUN/xguardd.pid
FIFO=$XG_RUN/events

is_running() {
  _p=$(cat "$PIDF" 2>/dev/null); case "$_p" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$_p" 2>/dev/null || return 1
  case "$(tr '\0' ' ' <"/proc/$_p/cmdline" 2>/dev/null)" in *xguardd.sh*) return 0 ;; esac
  return 1
}

producers() {
  ip monitor route 2>/dev/null | while read -r _; do echo "net changed"; done >"$FIFO" &

  _w="$XG_CFG:wmy"
  for _id in $(feat_list); do mkdir -p "$XG_DATA/$_id"; _w="$_w $XG_DATA/$_id:wmy"; done
  bb inotifyd - $_w 2>/dev/null | while read -r _ev _dir _file; do
    case "$_dir" in
      "$XG_CFG") echo "config ${_file:-settings.prop}" ;;
      *) [ "$_file" = config.json ] && echo "config ${_dir##*/}/config.json" ;;
    esac
  done >"$FIFO" &

  ( while :; do sleep 900; echo "tick 15"; done ) >"$FIFO" &
  ( while :; do sleep 30; echo "splash repair"; done ) >"$FIFO" &
}

dispatch() {   # dispatch <event> <arg>
  for id in $(feat_for_event "$1"); do
    if lock_try "ev.$id"; then
      ( feat_run "$id" on_event "$1" "$2"; lock_free "ev.$id" ) &
    fi
  done
}

main_loop() {
  last_key=""; last_ts=0
  while :; do
    while read -r ev arg; do
      now=$(date +%s)
      key="$ev $arg"
      [ "$key" = "$last_key" ] && [ $((now - last_ts)) -lt 2 ] && continue
      last_key=$key; last_ts=$now
      echo "$key" >"$XG_STATE/last_event"
      case "$ev" in
        screen|charging) echo "$arg" >"$XG_STATE/$ev" ;;
        foreground) echo "$arg" >"$XG_STATE/foreground" ;;
      esac
      dispatch "$ev" "$arg"
    done <"$FIFO"
  done
}

case "${1:-start}" in
  start)
    is_running && exit 0
    rm -f "$FIFO"; mkfifo "$FIFO"
    rm -rf "$XG_RUN"/ev.*.lock 2>/dev/null
    echo $$ >"$PIDF"
    producers
    log xguardd "已启动 pid=$(cat "$PIDF")"
    exec 3<>"$FIFO"
    main_loop ;;
  stop)
    if is_running; then
      pid=$(cat "$PIDF")
      kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null
      log xguardd "已停止"
    fi
    rm -f "$PIDF" "$FIFO" ;;
  status)
    is_running && echo "running $(cat "$PIDF")" || echo stopped ;;
  emit)  # 手动注入事件：xguardd.sh emit screen off
    shift; [ -p "$FIFO" ] && echo "$*" >"$FIFO" ;;
esac
