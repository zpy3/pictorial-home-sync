#!/system/bin/sh
PHS_PKG=com.local.pictorialhomesync
# Legacy SystemUI bake path (RealmeUI / older ColorOS). ColorOS 17 often stops updating it.
PHS_SRC_CACHE=/data/user_de/0/com.android.systemui/files/wallpaper/pictorialWallpaperCache.dat
PHS_SRC=$PHS_SRC_CACHE
# ColorOS 17+: current lock image is tracked here; bytes live in pictorial .ppic files.
PHS_SHOW_STAT=/data/data/com.heytap.pictorial/files/mmkv/SystemuiShowStat
# 亮屏/解锁换图时，乐划会提前写入下一张；锁频亮屏瞬间已是新图，show_num 可能稍后才更新
PHS_CORE_CACHE=/data/data/com.heytap.pictorial/files/mmkv/core_reboot_caches
PHS_COMMON_MMKV=/data/data/com.heytap.pictorial/files/mmkv/CommonMMKV
PHS_PIC_DIR=/data/media/0/Android/data/com.heytap.pictorial/files/pic
# SystemUI / 乐划写入的「当前锁频」官方 URI（比 MMKV show_num 可靠）
PHS_SET_KEYGUARD_URI=oplus_customize_keyguard_current_pictorial_uri
PHS_SET_FILE_URI=pictorial_file_uri
PHS_STAGE=/data/local/tmp/phs_wall.jpg
PHS_APPFILE=/data/data/com.local.pictorialhomesync/files/wall.jpg
PHS_OK=/data/data/com.local.pictorialhomesync/files/last_ok
PHS_FAIL=/data/data/com.local.pictorialhomesync/files/last_fail
PHS_STATE=/data/local/tmp/pictorial_home_sync.last
PHS_LOCK=/data/local/tmp/pictorial_home_sync.lock
PHS_PENDING=/data/local/tmp/pictorial_home_sync.pending
PHS_LOG=/data/local/tmp/pictorial_home_sync.log
PHS_PID=/data/local/tmp/pictorial_home_sync.pid
PHS_RUN=/data/local/tmp/pictorial_home_sync.run
PHS_SHOW_FP=/data/local/tmp/pictorial_home_sync.showfp
PHS_SHOW_SN=/data/local/tmp/pictorial_home_sync.shownum
PHS_NEED_WM=/data/local/tmp/pictorial_home_sync.need_wm
PHS_HOLD=/data/local/tmp/pictorial_home_sync.hold
PHS_FROZEN=/data/local/tmp/pictorial_home_sync.frozen
PHS_PREFER_SHOW=/data/local/tmp/pictorial_home_sync.prefer_show
PHS_PREFER_NEXT=/data/local/tmp/pictorial_home_sync.prefer_next
PHS_GEN=/data/local/tmp/pictorial_home_sync.gen
PHS_WM_LOCK=/data/local/tmp/pictorial_home_sync.wm_lock
PHS_DEBOUNCE=/data/local/tmp/pictorial_home_sync.debounce
PHS_BL=/sys/class/backlight/panel0-backlight/brightness

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

# ColorOS 17: max show_num. IDs are long decimals; reject short junk matches.
# prints: "<groupId> <imageId> <show_num>" or empty
phs_current_show_ids() {
  [ -f "$PHS_SHOW_STAT" ] || return 1
  strings "$PHS_SHOW_STAT" 2>/dev/null | awk '
    /\{/ && /"groupId":"/ && /"id":"/ && /"show_num":"/ {
      json=$0
      sn=0; gid=""; iid=""
      if (match(json, /"show_num":"[0-9]+/)) {
        s=substr(json, RSTART, RLENGTH)
        sub(/.*"show_num":"/, "", s)
        sn=s+0
      }
      if (sn <= 0) next
      if (match(json, /"groupId":"[0-9]+"/)) {
        s=substr(json, RSTART, RLENGTH); split(s, a, "\""); gid=a[4]
      }
      if (match(json, /"id":"[0-9]+"/)) {
        s=substr(json, RSTART, RLENGTH); split(s, a, "\""); iid=a[4]
      }
      if (length(gid) < 12 || length(iid) < 12) next
      if (sn > best) { best=sn; bestg=gid; besti=iid }
    }
    END {
      if (besti == "") exit 1
      print bestg, besti, best
    }
  '
}

# 乐划为「下次亮屏」准备的图。prints: "<groupId> <imageId>"（gid 可空）
phs_next_light_ids() {
  # 同一条 JSON 里成对取出，避免 group_key / imageId 错位拼出脏 gid
  pair=$(strings "$PHS_CORE_CACHE" 2>/dev/null | awk '
    /next_light_imageid/ && /imageId/ {
      line=$0; gid=""; iid=""
      if (match(line, /"imageId":"[0-9]+"/)) {
        s=substr(line, RSTART, RLENGTH); split(s, a, "\""); iid=a[4]
      }
      if (match(line, /"groupId":"[0-9]+"/)) {
        s=substr(line, RSTART, RLENGTH); split(s, a, "\""); gid=a[4]
      }
      if (length(iid) >= 12) { lastg=gid; lasti=iid }
    }
    END {
      if (lasti == "") exit 1
      if (length(lastg) < 12) lastg="-"
      print lastg, lasti
    }
  ')
  if [ -z "$pair" ]; then
    pair=$(strings "$PHS_COMMON_MMKV" 2>/dev/null | awk '
      /light_image_id/ && /imageId/ {
        line=$0; gid=""; iid=""
        if (match(line, /"imageId":"[0-9]+"/)) {
          s=substr(line, RSTART, RLENGTH); split(s, a, "\""); iid=a[4]
        }
        if (match(line, /"groupId":"[0-9]+"/)) {
          s=substr(line, RSTART, RLENGTH); split(s, a, "\""); gid=a[4]
        }
        if (length(iid) >= 12) { lastg=gid; lasti=iid }
      }
      END {
        if (lasti == "") exit 1
        if (length(lastg) < 12) lastg="-"
        print lastg, lasti
      }
    ')
  fi
  [ -n "$pair" ] || return 1
  echo "$pair"
}

phs_find_ppic() {
  gid="$1"
  iid="$2"
  [ -n "$iid" ] || return 1
  [ -d "$PHS_PIC_DIR" ] || return 1
  f=""
  # 乐划 ppic 多为点文件，普通 * 通配匹配不到前导点
  if [ -n "$gid" ] && [ "$gid" != "-" ]; then
    f=$(ls "$PHS_PIC_DIR"/."${gid}_${iid}_"*.ppic 2>/dev/null | head -1)
  fi
  if [ -z "$f" ]; then
    f=$(ls "$PHS_PIC_DIR"/.*"_${iid}_"*.ppic 2>/dev/null | head -1)
  fi
  if [ -z "$f" ]; then
    f=$(ls "$PHS_PIC_DIR"/*"_${iid}_"*.ppic 2>/dev/null | head -1)
  fi
  [ -n "$f" ] && [ -s "$f" ] || return 1
  case "$(od -An -tx1 -N 3 "$f" 2>/dev/null | tr -d ' \n')" in
    ffd8ff) echo "$f"; return 0 ;;
  esac
  sz=$(stat -c %s "$f" 2>/dev/null)
  [ -n "$sz" ] && [ "$sz" -gt 10240 ] && { echo "$f"; return 0; }
  return 1
}

# --- settings URI（主信号）---
# pictorial_file_uri：实测亮屏/换图后会更新，指向当前 .ppic，并带 next=gid_iid
# keyguard_current_pictorial_uri：可能陈旧（文件不存在），仅作次选

phs_settings_get() {
  settings get system "$1" 2>/dev/null
}

# 从 content://.../pic/.gid_iid_....ppic?... 取出文件名
phs_uri_basename() {
  echo "$1" | sed -n 's|.*/pic/\([^?]*\).*|\1|p'
}

# next=gid_iid
phs_uri_next_pair() {
  echo "$1" | sed -n 's/.*[?&]next=\([^&]*\).*/\1/p'
}

# 当前应跟随的 URI：file_uri 优先（会随换图变）；keyguard 仅当其文件存在时
phs_current_lock_uri() {
  f=$(phs_settings_get "$PHS_SET_FILE_URI")
  k=$(phs_settings_get "$PHS_SET_KEYGUARD_URI")
  fb=$(phs_uri_basename "$f")
  kb=$(phs_uri_basename "$k")
  if [ -n "$fb" ] && [ -f "$PHS_PIC_DIR/$fb" ]; then
    echo "$f"
    return 0
  fi
  if [ -n "$kb" ] && [ -f "$PHS_PIC_DIR/$kb" ]; then
    echo "$k"
    return 0
  fi
  # 文件尚未落盘时仍返回 file_uri，便于检测变化
  if [ -n "$fb" ]; then
    echo "$f"
    return 0
  fi
  if [ -n "$kb" ]; then
    echo "$k"
    return 0
  fi
  return 1
}

phs_uri_to_path() {
  b=$(phs_uri_basename "$1")
  [ -n "$b" ] || return 1
  [ -f "$PHS_PIC_DIR/$b" ] || return 1
  echo "$PHS_PIC_DIR/$b"
}

# next= 对应本地 ppic（预铺用）
phs_uri_next_path() {
  pair=$(phs_uri_next_pair "$1")
  [ -n "$pair" ] || return 1
  gid=$(echo "$pair" | cut -d_ -f1)
  iid=$(echo "$pair" | cut -d_ -f2)
  [ -n "$iid" ] || return 1
  phs_find_ppic "$gid" "$iid"
}

# Apply gid/iid[/sn] into PHS_SRC. tag=show|light|uri
phs_use_pic() {
  _gid="$1"; _iid="$2"; _sn="$3"; _tag="$4"
  [ -n "$_iid" ] || return 1
  _ppic=$(phs_find_ppic "$_gid" "$_iid")
  [ -n "$_ppic" ] || return 1
  PHS_SRC=$_ppic
  PHS_CUR_SN=$_sn
  if [ -n "$_sn" ]; then
    echo "${_gid}:${_iid}:${_sn}" > "$PHS_SHOW_FP" 2>/dev/null
  else
    echo "${_tag}:${_gid}:${_iid}" > "$PHS_SHOW_FP" 2>/dev/null
  fi
  return 0
}

phs_use_path() {
  _path="$1"; _tag="$2"
  [ -s "$_path" ] || return 1
  PHS_SRC=$_path
  PHS_CUR_SN=
  base=$(basename "$_path")
  # .gid_iid_rest.ppic
  _gid=$(echo "$base" | sed -n 's/^\.\([0-9]*\)_.*/\1/p')
  _iid=$(echo "$base" | sed -n 's/^\.[0-9]*_\([0-9]*\)_.*/\1/p')
  echo "${_tag}:${_gid}:${_iid}" > "$PHS_SHOW_FP" 2>/dev/null
  return 0
}

# Remember gid/iid that lock↔home should share for this wake.
phs_set_hold_from_fp() {
  fp=$(cat "$PHS_SHOW_FP" 2>/dev/null)
  [ -n "$fp" ] || return 1
  echo "$fp" | awk -F: '
    $1=="light" || $1=="hold" || $1=="show" || $1=="uri" || $1=="next" {
      if (NF>=3) { print $2, $3; exit }
    }
    NF>=2 { print $1, $2; exit }
  ' > "$PHS_HOLD"
}

# Resolve：只跟 pictorial_file_uri 当前图（息屏换图灭屏时 URI 已是新图）。
# 不再用 next= / next_light 预铺——实测 next 常陈旧，会盖错再被亮屏纠正 → 换图动画。
phs_resolve_src() {
  PHS_CUR_SN=
  uri=$(phs_current_lock_uri)

  if [ -n "$uri" ]; then
    up=$(phs_uri_to_path "$uri")
    if [ -n "$up" ]; then
      phs_use_path "$up" uri && return 0
    fi
  fi

  ids=$(phs_current_show_ids)
  if [ -n "$ids" ]; then
    phs_use_pic "$(echo "$ids" | awk '{print $1}')" \
                "$(echo "$ids" | awk '{print $2}')" \
                "$(echo "$ids" | awk '{print $3}')" show && return 0
  fi

  if [ -s "$PHS_SRC_CACHE" ]; then
    PHS_SRC=$PHS_SRC_CACHE
    return 0
  fi
  return 1
}

# 变化指纹：settings URI 全文（变了就是换图）
phs_show_fingerprint() {
  uri=$(phs_current_lock_uri)
  if [ -n "$uri" ]; then
    echo "U:$uri"
    return 0
  fi
  ids=$(phs_current_show_ids)
  if [ -n "$ids" ]; then
    echo "S:$(echo "$ids" | awk '{print $1":"$2":"$3}')"
    return 0
  fi
  return 1
}

# 便宜探测：直接读 settings（比 cksum MMKV 更准）
phs_show_stat_cookie() {
  phs_settings_get "$PHS_SET_FILE_URI"
  phs_settings_get "$PHS_SET_KEYGUARD_URI"
}

# 屏状态：不能只看 backlight。屏下指纹认证时 brightness 常被拉到 0，
# 但 PowerManager 仍是 Awake —— 误判灭屏会用 next_light 盖回旧桌面。
# 策略：亮度>0 必亮；亮度=0 再问 mWakefulness（~15ms）。
phs_wakefulness() {
  w=$(dumpsys power 2>/dev/null | grep -m1 'mWakefulness=')
  w=${w#*mWakefulness=}
  w=${w%%[[:space:]]*}
  w=${w%%,*}
  case "$w" in
    Awake|1) echo Awake ;;
    Dreaming|2) echo Dreaming ;;
    Dozing|3) echo Dozing ;;
    Asleep|0) echo Asleep ;;
    *) echo Unknown ;;
  esac
}

phs_screen_on() {
  b=$(cat "$PHS_BL" 2>/dev/null)
  case "$b" in
    ''|*[!0-9]*) ;;
    0) ;;
    *) return 0 ;;
  esac
  case "$(phs_wakefulness)" in
    Awake|Dreaming) return 0 ;;
    *) return 1 ;;
  esac
}

phs_warm_helper() {
  # ColorOS kills stopped apps — provider then 404 for ~1s. Wake without setting wallpaper.
  am start --user 0 -n $PHS_PKG/.SetActivity --es path /dev/null --es md5 warm >/dev/null 2>&1
}

phs_ensure_apk() {
  if ! pm path "$PHS_PKG" >/dev/null 2>&1; then
    APK="$(phs_moddir)/common/pictorial-home-sync.apk"
    [ -f "$APK" ] && { pm install -r -g "$APK" >/dev/null 2>&1 || pm install -r "$APK" >/dev/null 2>&1; }
    phs_warm_helper
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

# Wait until pictorial cache stops changing (large writes while screen-off).
phs_stable_md5() {
  prev=""
  i=0
  while [ $i -lt 10 ]; do
    [ -s "$PHS_SRC" ] || return 1
    cur=$(md5sum "$PHS_SRC" 2>/dev/null | awk '{print $1}')
    [ -n "$cur" ] || return 1
    if [ -n "$prev" ] && [ "$cur" = "$prev" ]; then
      echo "$cur"
      return 0
    fi
    prev=$cur
    phs_sleep 0.35
    i=$((i + 1))
  done
  [ -n "$prev" ] && echo "$prev" && return 0
  return 1
}

phs_helper_apk() {
  echo "$(phs_moddir)/common/pictorial-home-sync.apk"
}

# Silent WallpaperManager via app_process (no Activity flash; works under keyguard).
phs_cli_set() {
  path="$1"
  md5="$2"
  apk=$(phs_helper_apk)
  [ -f "$apk" ] || apk=$(pm path "$PHS_PKG" 2>/dev/null | head -1 | cut -d: -f2)
  [ -f "$apk" ] || return 1
  CLASSPATH="$apk" /system/bin/app_process /system/bin \
    com.local.pictorialhomesync.WallpaperCli "$path" "$md5" >/dev/null 2>&1
}

# Prepare app-readable copy of staged wallpaper.
phs_prep_apppath() {
  apppath="$PHS_APPFILE"
  if mkdir -p /data/data/$PHS_PKG/files 2>/dev/null; then
    cp -f "$PHS_STAGE" "$apppath" 2>/dev/null || apppath="$PHS_STAGE"
    APPUID=$(stat -c %u /data/data/$PHS_PKG 2>/dev/null)
    [ -n "$APPUID" ] && chown ${APPUID}:${APPUID} /data/data/$PHS_PKG/files "$apppath" 2>/dev/null
    chmod 600 "$apppath" 2>/dev/null
  else
    apppath="$PHS_STAGE"
  fi
  [ -s "$apppath" ] || apppath="$PHS_STAGE"
  echo "$apppath"
}

# WallpaperManager via content provider. Keep helper warm to avoid double cost.
phs_launch_setter() {
  md5="$1"
  rm -f "$PHS_OK" "$PHS_FAIL"
  apppath=$(phs_prep_apppath)

  content call --user 0 --uri content://com.local.pictorialhomesync.set \
    --method set --extra path:s:"$apppath" --extra md5:s:"$md5" >/dev/null 2>&1
  ok=$(cat "$PHS_OK" 2>/dev/null | tr -d '\r\n')
  if [ "$ok" = "$md5" ]; then
    return 0
  fi

  # Provider missing (app stopped) — warm once, single retry
  phs_warm_helper
  phs_sleep 0.05
  rm -f "$PHS_OK"
  content call --user 0 --uri content://com.local.pictorialhomesync.set \
    --method set --extra path:s:"$apppath" --extra md5:s:"$md5" >/dev/null 2>&1
  ok=$(cat "$PHS_OK" 2>/dev/null | tr -d '\r\n')
  [ "$ok" = "$md5" ] && return 0

  # Last resort: Activity (may flash). Wait for last_ok — do not fake success.
  rm -f "$PHS_OK"
  am start --user 0 -f 0x10000000 -n $PHS_PKG/.SetActivity \
    --es path "$apppath" --es md5 "$md5" >/dev/null 2>&1 || return 1
  phs_wait_ok "$md5" 8
}

# Magisk/root: write AOSP wallpaper file so desktop is ready before unlock.
phs_set_wallpaper_root() {
  src="$1"
  [ -s "$src" ] || return 1
  dest=/data/system/users/0/wallpaper
  dest_orig=/data/system/users/0/wallpaper_orig
  cp -f "$src" "$dest" 2>/dev/null || return 1
  cp -f "$src" "$dest_orig" 2>/dev/null
  chown system:system "$dest" "$dest_orig" 2>/dev/null
  chmod 600 "$dest" "$dest_orig" 2>/dev/null
  restorecon "$dest" "$dest_orig" 2>/dev/null
  service call wallpaper 8 i32 1 >/dev/null 2>&1
  service call wallpaper 5 i32 1 >/dev/null 2>&1
  return 0
}

phs_wait_ok() {
  md5="$1"
  limit=${2:-12}
  n=0
  while [ $n -lt "$limit" ]; do
    ok=$(cat "$PHS_OK" 2>/dev/null | tr -d '\r\n')
    [ "$ok" = "$md5" ] && return 0
    phs_sleep 0.2
    n=$((n + 1))
  done
  return 1
}

phs_sync_once() {
  [ -n "$PHS_WANT_NEXT" ] && echo 1 > "$PHS_PREFER_NEXT"
  phs_resolve_src || return 1
  [ -s "$PHS_SRC" ] || return 1

  if [ -z "$PHS_FORCE" ] && [ -f "$PHS_LOCK" ]; then
    old=$(cat "$PHS_LOCK" 2>/dev/null); now=$(date +%s)
    # 仅短暂互斥；勿堵到 WallpaperManager 跑完，否则新锁频图会被挡住
    if [ -n "$old" ] && [ $((now - old)) -lt 2 ]; then
      echo 1 > "$PHS_PENDING"
      return 0
    fi
  fi
  date +%s > "$PHS_LOCK"

  # Always take the latest under lock
  phs_resolve_src || { rm -f "$PHS_LOCK" "$PHS_PREFER_NEXT"; return 1; }
  rm -f "$PHS_PREFER_NEXT" "$PHS_PREFER_SHOW"

  if [ "$PHS_SRC" = "$PHS_SRC_CACHE" ]; then
    cur=$(phs_stable_md5) || { rm -f "$PHS_LOCK"; return 1; }
  else
    cur=$(md5sum "$PHS_SRC" 2>/dev/null | awk '{print $1}')
    [ -n "$cur" ] || { rm -f "$PHS_LOCK"; return 1; }
  fi

  last=$(cat "$PHS_STATE" 2>/dev/null)
  need_wm=0
  [ -f "$PHS_NEED_WM" ] && need_wm=1
  # Same image already landed — only WM retry if previously failed
  if [ -z "$PHS_FORCE" ] && [ -n "$cur" ] && [ "$cur" = "$last" ] && [ "$need_wm" = "0" ]; then
    [ -n "$PHS_CUR_SN" ] && echo "$PHS_CUR_SN" > "$PHS_SHOW_SN"
    rm -f "$PHS_LOCK" "$PHS_PENDING"
    return 0
  fi

  phs_ensure_apk
  if [ "$cur" != "$last" ] || [ ! -s "$PHS_STAGE" ]; then
    cp -f "$PHS_SRC" "$PHS_STAGE" || { echo 1 > "$PHS_PENDING"; rm -f "$PHS_LOCK"; return 1; }
    chmod 644 "$PHS_STAGE" 2>/dev/null
    copy=$(md5sum "$PHS_STAGE" 2>/dev/null | awk '{print $1}')
    if [ "$copy" != "$cur" ]; then
      phs_log "copy race cur=$cur copy=$copy"
      echo 1 > "$PHS_PENDING"
      rm -f "$PHS_LOCK"
      return 1
    fi
    phs_set_wallpaper_root "$PHS_STAGE"
  fi
  echo "$cur" > "$PHS_STATE"
  [ -n "$PHS_CUR_SN" ] && echo "$PHS_CUR_SN" > "$PHS_SHOW_SN"
  gen=$(cat "$PHS_GEN" 2>/dev/null)
  case "$gen" in ''|*[!0-9]*) gen=0 ;; esac
  gen=$((gen + 1))
  echo "$gen" > "$PHS_GEN"

  sn_log=${PHS_CUR_SN:-?}
  src_log=$(basename "$PHS_SRC")
  rm -f "$PHS_OK" "$PHS_FAIL" "$PHS_LOCK"

  # 灭屏：同步等待 WM 完成，保证亮屏解锁前桌面已换好
  # 亮屏：后台串行 WM，且只认最新 gen
  if ! phs_screen_on; then
    if phs_launch_setter "$cur"; then
      rm -f "$PHS_NEED_WM" "$PHS_PENDING"
      phs_log "synced${PHS_FORCE:+(force)} sn=$sn_log $cur src=$src_log on=0 gen=$gen"
    else
      echo 1 > "$PHS_NEED_WM"
      echo 1 > "$PHS_PENDING"
      phs_log "file ready, WM pending sn=$sn_log $cur gen=$gen"
    fi
    return 0
  fi

  (
    w=0
    while ! mkdir "$PHS_WM_LOCK" 2>/dev/null; do
      [ "$(cat "$PHS_GEN" 2>/dev/null)" = "$gen" ] || exit 0
      [ "$(cat "$PHS_STATE" 2>/dev/null)" = "$cur" ] || exit 0
      phs_sleep 0.05
      w=$((w + 1))
      [ "$w" -gt 80 ] && exit 0
    done
    if [ "$(cat "$PHS_GEN" 2>/dev/null)" != "$gen" ] || [ "$(cat "$PHS_STATE" 2>/dev/null)" != "$cur" ]; then
      rmdir "$PHS_WM_LOCK" 2>/dev/null
      exit 0
    fi
    if phs_launch_setter "$cur"; then
      if [ "$(cat "$PHS_GEN" 2>/dev/null)" = "$gen" ]; then
        rm -f "$PHS_NEED_WM" "$PHS_PENDING"
        phs_log "synced${PHS_FORCE:+(force)} sn=$sn_log $cur src=$src_log on=1 gen=$gen"
      else
        phs_log "synced stale ignored sn=$sn_log gen=$gen"
      fi
    else
      if [ "$(cat "$PHS_GEN" 2>/dev/null)" = "$gen" ]; then
        echo 1 > "$PHS_NEED_WM"
        echo 1 > "$PHS_PENDING"
        phs_log "file ready, WM pending sn=$sn_log $cur gen=$gen"
      fi
    fi
    rmdir "$PHS_WM_LOCK" 2>/dev/null
  ) &
  return 0
}

phs_sync_catchup() {
  n=0
  while [ $n -lt 3 ]; do
    phs_sync_once
    [ -f "$PHS_PENDING" ] || [ -f "$PHS_NEED_WM" ] || break
    n=$((n + 1))
  done
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
