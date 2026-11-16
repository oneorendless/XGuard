#!/system/bin/sh
# Real network observations; panel edits are separate audit events.
exec sh "$XG_MODDIR/core/monitor.sh" "${1:-list}"
