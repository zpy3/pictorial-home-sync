#!/system/bin/sh
# Magisk late_start: must nsenter+setsid immediately — background (&) alone is reaped on exit.
MODDIR=${0%/*}
MODDIR=$(cd "$MODDIR" 2>/dev/null && pwd) || MODDIR=/data/adb/modules/pictorial_home_sync
. "$MODDIR/common/lib.sh"
export MODDIR

rm -f /data/adb/service.d/pictorial_home_sync.sh \
      /data/adb/service.d/pictorial_home_sync_handler.sh 2>/dev/null

[ "$(cat "$MODDIR/config/enabled" 2>/dev/null)" = "1" ] || {
  phs_log "service.sh: disabled, skip"
  exit 0
}

chmod 755 "$MODDIR/common/"*.sh 2>/dev/null
phs_log "service.sh: spawn boot worker"
phs_spawn_detached "$MODDIR" "$MODDIR/common/boot.sh" boot
exit 0
