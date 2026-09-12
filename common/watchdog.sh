#!/system/bin/sh
# Shell watchdog in init mnt ns — recovers daemon if Magisk action reaps it.
# Not app-side su.
MODDIR="${MODDIR:-/data/adb/modules/pictorial_home_sync}"
[ -f "$MODDIR/module.prop" ] || MODDIR=/data/adb/modules/pictorial_home_sync
. "$MODDIR/common/lib.sh"
export MODDIR

phs_log "watchdog start pid=$$ ppid=$PPID"

while true; do
  phs_sleep 12
  [ "$(cat "$MODDIR/config/enabled" 2>/dev/null)" = "1" ] || continue
  if phs_daemon_alive >/dev/null; then
    continue
  fi
  phs_log "watchdog: restart daemon (nsenter)"
  export PHS_DAEMONIZED=1
  if [ -x /system/bin/nsenter ] && [ -r /proc/1/ns/mnt ]; then
    /system/bin/nsenter -t 1 -m -- /system/bin/sh -c \
      "setsid /system/bin/sh '$MODDIR/common/daemon.sh' </dev/null >>'$PHS_LOG' 2>&1 & echo \$! > '$PHS_PID'"
  elif command -v setsid >/dev/null 2>&1; then
    setsid /system/bin/sh "$MODDIR/common/daemon.sh" </dev/null >>"$PHS_LOG" 2>&1 &
    echo $! > "$PHS_PID"
  else
    /system/bin/sh "$MODDIR/common/daemon.sh" </dev/null >>"$PHS_LOG" 2>&1 &
    echo $! > "$PHS_PID"
  fi
done
