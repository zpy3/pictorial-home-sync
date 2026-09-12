#!/system/bin/sh
PHS_PKG=com.local.pictorialhomesync
PHS_SRC=/data/user_de/0/com.android.systemui/files/wallpaper/pictorialWallpaperCache.dat
PHS_APPFILE=/data/data/com.local.pictorialhomesync/files/wall.jpg
PHS_STATE=/data/local/tmp/pictorial_home_sync.last
PHS_LOCK=/data/local/tmp/pictorial_home_sync.lock
PHS_LOG=/data/local/tmp/pictorial_home_sync.log
PHS_PID=/data/local/tmp/pictorial_home_sync.pid
PHS_RUN=/data/local/tmp/pictorial_home_sync.run

# Magisk mount-ns / ASH_STANDALONE 下 /system/bin/sleep 常不可用，统一走 busybox/toybox
phs_sleep() {
  if [ -x /data/adb/magisk/busybox ]; then
    /data/adb/magisk/busybox sleep "$@"
  elif [ -x /data/adb/ksu/bin/busybox ]; then
    /data/adb/ksu/bin/busybox sleep "$@"
  elif [ -x /system/bin/toybox ]; then
    /system/bin/toybox sleep "$@"
  else
    sleep "$@"
  fi
}

phs_pgrep() {
  # Use ps (fast). Raw /proc/[0-9]* globs break on ColorOS (e.g. 8350_reg) and can hang Magisk action.
  ps -A -o PID=,ARGS= 2>/dev/null | grep -F -- "$1" | grep -v grep | while read -r pid rest; do
    case "$pid" in
      *[!0-9]*) ;;
      *) echo "$pid" ;;
    esac
  done
}

phs_log() { echo "$(date '+%F %T') $*" >> "$PHS_LOG"; }

phs_moddir() {
  if [ -n "$MODDIR" ] && [ -f "$MODDIR/module.prop" ]; then
    # Always absolute — Magisk Alpha runs: cd $MOD && sh ./action.sh (MODDIR would be ".")
    _d=$(cd "$MODDIR" 2>/dev/null && pwd)
    [ -n "$_d" ] && [ -f "$_d/module.prop" ] && { echo "$_d"; return; }
  fi
  echo "/data/adb/modules/pictorial_home_sync"
}

phs_pictorial_present() {
  [ -f /product/app/Pictorial/Pictorial.apk ] && return 0
  [ -f /system/app/Pictorial/Pictorial.apk ] && return 0
  [ -f /system_ext/app/Pictorial/Pictorial.apk ] && return 0
  pm path com.heytap.pictorial >/dev/null 2>&1 && return 0
  cmd package path com.heytap.pictorial >/dev/null 2>&1 && return 0
  return 1
}

phs_ensure_apk() {
  if ! pm path "$PHS_PKG" >/dev/null 2>&1; then
    APK="$(phs_moddir)/common/pictorial-home-sync.apk"
    [ -f "$APK" ] && { pm install -r -g "$APK" >/dev/null 2>&1 || pm install -r "$APK" >/dev/null 2>&1; }
  fi
}

phs_daemon_alive() {
  # 1) pid file
  if [ -f "$PHS_PID" ]; then
    pid=$(cat "$PHS_PID" 2>/dev/null)
    if [ -n "$pid" ] && [ -r /proc/$pid/cmdline ]; then
      tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null | grep -q 'pictorial_home_sync/common/daemon.sh' && {
        echo "$pid"
        return 0
      }
    fi
  fi
  # 2) scan
  live=$(phs_pgrep 'pictorial_home_sync/common/daemon.sh')
  [ -n "$live" ] && { echo "$live"; return 0; }
  # 3) inotify watching our cache
  for pid in $(phs_pgrep inotifyd); do
    tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null | grep -q pictorialWallpaperCache && {
      echo "$pid"
      return 0
    }
  done
  return 1
}

phs_kill_daemons() {
  # Do NOT kill boot.sh here — boot worker calls phs_start_daemon and would suicide.
  for pid in $(phs_pgrep 'pictorial_home_sync/common/daemon.sh') \
             $(phs_pgrep 'pictorial_home_sync/common/handler.sh') \
             $(phs_pgrep 'pictorial_home_sync/common/watchdog.sh') \
             $(phs_pgrep 'pictorialWallpaperCache.dat') \
             $(phs_pgrep 'service.d/pictorial_home_sync'); do
    kill -9 "$pid" 2>/dev/null
  done
  for pid in $(phs_pgrep inotifyd); do
    tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null | grep -q pictorial && kill -9 "$pid" 2>/dev/null
  done
  # pid file leftover
  if [ -f "$PHS_PID" ]; then
    opid=$(cat "$PHS_PID" 2>/dev/null)
    [ -n "$opid" ] && kill -9 "$opid" 2>/dev/null
  fi
  rm -f "$PHS_PID" "$PHS_RUN" \
        /data/adb/service.d/pictorial_home_sync.sh \
        /data/adb/service.d/pictorial_home_sync_handler.sh 2>/dev/null
}

phs_sync_once() {
  [ -s "$PHS_SRC" ] || return 1
  if [ -z "$PHS_FORCE" ] && [ -f "$PHS_LOCK" ]; then
    old=$(cat "$PHS_LOCK" 2>/dev/null); now=$(date +%s)
    [ -n "$old" ] && [ $((now - old)) -lt 8 ] && return 0
  fi
  date +%s > "$PHS_LOCK"
  phs_sleep 0.25
  cur=$(md5sum "$PHS_SRC" 2>/dev/null | awk '{print $1}')
  last=$(cat "$PHS_STATE" 2>/dev/null)
  if [ -z "$PHS_FORCE" ] && [ -n "$cur" ] && [ "$cur" = "$last" ]; then
    rm -f "$PHS_LOCK"
    return 0
  fi
  [ -n "$cur" ] || { rm -f "$PHS_LOCK"; return 1; }

  phs_ensure_apk
  mkdir -p /data/data/$PHS_PKG/files
  cp -f "$PHS_SRC" "$PHS_APPFILE" || { rm -f "$PHS_LOCK"; return 1; }
  APPUID=$(stat -c %u /data/data/$PHS_PKG 2>/dev/null)
  [ -n "$APPUID" ] && chown ${APPUID}:${APPUID} /data/data/$PHS_PKG/files "$PHS_APPFILE"
  chmod 600 "$PHS_APPFILE"
  # never block Magisk action on am
  am start --user 0 -n $PHS_PKG/.SetActivity --es path "$PHS_APPFILE" >/dev/null 2>&1 &
  echo "$cur" > "$PHS_STATE"
  phs_log "synced${PHS_FORCE:+(force)} $cur"
  rm -f "$PHS_LOCK"
}

# Escape Magisk Alpha action mount-ns into init's, then setsid.
# setsid alone is NOT enough under Magisk Manager action.
phs_spawn_daemon_magisk_safe() {
  MD="$1"
  STARTER="/data/local/tmp/phs_init_spawn.sh"
  cat > "$STARTER" << EOF
#!/system/bin/sh
export PHS_DAEMONIZED=1
export MODDIR=$MD
export PATH=/system/bin:/system/xbin:/product/bin:/vendor/bin:/data/adb/magisk
cd / || true
DAEMON=$MD/common/daemon.sh
if [ ! -f "\$DAEMON" ]; then
  echo "missing daemon \$DAEMON" >> $PHS_LOG
  exit 1
fi
if [ -x /system/bin/setsid ]; then
  exec /system/bin/setsid /system/bin/sh "\$DAEMON"
elif command -v setsid >/dev/null 2>&1; then
  exec setsid /system/bin/sh "\$DAEMON"
else
  exec /system/bin/sh "\$DAEMON"
fi
EOF
  chmod 755 "$STARTER"

  if [ -x /system/bin/nsenter ] && [ -r /proc/1/ns/mnt ]; then
    # Enter init mount namespace, then background the starter (escape Magisk action mnt/session)
    /system/bin/nsenter -t 1 -m -- /system/bin/sh -c \
      "/system/bin/sh '$STARTER' </dev/null >>'$PHS_LOG' 2>&1 & echo \$! > '$PHS_PID'"
    phs_log "spawn via nsenter -t 1 -m"
  else
    /system/bin/sh "$STARTER" </dev/null >>"$PHS_LOG" 2>&1 &
    echo $! > "$PHS_PID"
    phs_log "spawn fallback (no nsenter)"
  fi
  phs_sleep 0.15
  rm -f "$STARTER" 2>/dev/null
}

phs_start_daemon() {
  MD="$(phs_moddir)"
  chmod 755 "$MD/service.sh" "$MD/action.sh" \
    "$MD/common/handler.sh" "$MD/common/lib.sh" \
    "$MD/common/daemon.sh" "$MD/common/watchdog.sh" "$MD/common/boot.sh" 2>/dev/null
  phs_kill_daemons
  phs_ensure_apk

  # Spawn ASAP so Magisk Alpha teardown / early kill cannot win the race
  phs_spawn_daemon_magisk_safe "$MD"

  i=0
  live=""
  while [ $i -lt 8 ]; do
    live=$(phs_daemon_alive)
    [ -n "$live" ] && break
    phs_sleep 0.15
    i=$((i + 1))
  done
  phs_log "daemon live after start: ${live:-none}"
  # shell watchdog only (no app-side su)
  phs_ensure_watchdog "$MD"
  [ -n "$live" ]
}

phs_ensure_watchdog() {
  MD="$1"
  [ -n "$(phs_pgrep 'pictorial_home_sync/common/watchdog.sh')" ] && return 0
  WD_STARTER="/data/local/tmp/phs_wd_spawn.sh"
  cat > "$WD_STARTER" << EOF
#!/system/bin/sh
export MODDIR=$MD
export PATH=/system/bin:/system/xbin:/product/bin:/vendor/bin:/data/adb/magisk
cd / || true
WD=$MD/common/watchdog.sh
if [ ! -f "\$WD" ]; then exit 1; fi
if [ -x /system/bin/setsid ]; then
  exec /system/bin/setsid /system/bin/sh "\$WD"
else
  exec /system/bin/sh "\$WD"
fi
EOF
  chmod 755 "$WD_STARTER"
  if [ -x /system/bin/nsenter ] && [ -r /proc/1/ns/mnt ]; then
    /system/bin/nsenter -t 1 -m -- /system/bin/sh -c \
      "/system/bin/sh '$WD_STARTER' </dev/null >>'$PHS_LOG' 2>&1 &"
  else
    /system/bin/sh "$WD_STARTER" </dev/null >>"$PHS_LOG" 2>&1 &
  fi
  phs_sleep 0.2
  rm -f "$WD_STARTER" 2>/dev/null
}

# Detach any long-lived worker into init mnt ns (for Magisk service.sh / action).
phs_spawn_detached() {
  MD="$1"
  SCRIPT="$2"
  TAG="$3"
  STARTER="/data/local/tmp/phs_detach_${TAG}.sh"
  cat > "$STARTER" << EOF
#!/system/bin/sh
export MODDIR=$MD
export PATH=/system/bin:/system/xbin:/product/bin:/vendor/bin:/data/adb/magisk
cd / || true
if [ -x /system/bin/setsid ]; then
  exec /system/bin/setsid /system/bin/sh "$SCRIPT"
else
  exec /system/bin/sh "$SCRIPT"
fi
EOF
  chmod 755 "$STARTER"
  if [ -x /system/bin/nsenter ] && [ -r /proc/1/ns/mnt ]; then
    /system/bin/nsenter -t 1 -m -- /system/bin/sh -c \
      "/system/bin/sh '$STARTER' </dev/null >>'$PHS_LOG' 2>&1 &"
    phs_log "detached $TAG via nsenter"
  else
    /system/bin/sh "$STARTER" </dev/null >>"$PHS_LOG" 2>&1 &
    phs_log "detached $TAG fallback"
  fi
  phs_sleep 0.1
  rm -f "$STARTER" 2>/dev/null
}
