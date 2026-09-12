#!/system/bin/sh
# Expect PHS_DAEMONIZED=1 when spawned via nsenter+setsid from action/service.
# Fallback self-detach for manual runs.
if [ -z "$PHS_DAEMONIZED" ]; then
  export PHS_DAEMONIZED=1
  LOG=/data/local/tmp/pictorial_home_sync.log
  if [ -x /system/bin/nsenter ] && [ -r /proc/1/ns/mnt ]; then
    /system/bin/nsenter -t 1 -m -- /system/bin/sh -c \
      "setsid /system/bin/sh \"$0\" </dev/null >>\"$LOG\" 2>&1 &"
  elif command -v setsid >/dev/null 2>&1; then
    setsid /system/bin/sh "$0" </dev/null >>"$LOG" 2>&1 &
  else
    /system/bin/sh "$0" </dev/null >>"$LOG" 2>&1 &
  fi
  exit 0
fi

MODDIR="${MODDIR:-${0%/*}/..}"
MODDIR=$(cd "$MODDIR" 2>/dev/null && pwd)
. "$MODDIR/common/lib.sh"
export MODDIR

echo $$ > "$PHS_PID"
echo $$ > "$PHS_RUN"
phs_log "daemon.sh start mod=$MODDIR pid=$$ ppid=$PPID"

# Do not block before inotify — Magisk may tear down action while we sync
(phs_sync_once) &

HANDLER="$MODDIR/common/handler.sh"
while true; do
  [ "$(cat "$MODDIR/config/enabled" 2>/dev/null)" = "1" ] || {
    phs_log "daemon exit: disabled"
    exit 0
  }
  if [ ! -e "$PHS_SRC" ]; then
    phs_sleep 1
    continue
  fi
  /system/bin/inotifyd "$HANDLER" "$PHS_SRC:wcmn"
  phs_sleep 0.2
done
