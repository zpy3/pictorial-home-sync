#!/system/bin/sh
# Survives Magisk service.sh teardown: wait for boot, then start daemon+watchdog.
MODDIR="${MODDIR:-/data/adb/modules/pictorial_home_sync}"
[ -f "$MODDIR/module.prop" ] || MODDIR=/data/adb/modules/pictorial_home_sync
. "$MODDIR/common/lib.sh"
export MODDIR

phs_log "boot worker start pid=$$ ppid=$PPID"

# Wait until PackageManager / boot is ready (service.sh often runs too early)
i=0
while [ $i -lt 120 ]; do
  bc=$(getprop sys.boot_completed 2>/dev/null)
  [ "$bc" = "1" ] && break
  phs_sleep 2
  i=$((i + 1))
done
phs_log "boot_completed=$(getprop sys.boot_completed 2>/dev/null)"

# Extra settle for ColorOS SystemUI / pictorial cache path
phs_sleep 8

[ "$(cat "$MODDIR/config/enabled" 2>/dev/null)" = "1" ] || {
  phs_log "boot worker exit: disabled"
  exit 0
}

# Prefer filesystem check; pm may still be flaky right after boot_completed
if ! phs_pictorial_present; then
  j=0
  while [ $j -lt 30 ]; do
    phs_pictorial_present && break
    phs_sleep 3
    j=$((j + 1))
  done
fi

if ! phs_pictorial_present; then
  phs_log "boot warn: pictorial not detected, start anyway"
else
  phs_log "boot: pictorial ok"
fi

# Start (and let watchdog keep it alive)
if phs_start_daemon; then
  PHS_FORCE=1 phs_sync_catchup
  phs_log "boot: daemon started"
else
  phs_log "boot: start failed, watchdog armed"
fi
exit 0
