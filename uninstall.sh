#!/system/bin/sh
# Magisk 卸载时执行。杀进程、清状态、卸辅助 App。

MODDIR=${0%/*}

# 停掉本模块相关进程（不碰乐划 com.heytap.pictorial）
for pat in \
  'pictorial_home_sync/common/daemon.sh' \
  'pictorial_home_sync/common/handler.sh' \
  'pictorial_home_sync/common/watchdog.sh' \
  'pictorial_home_sync/common/boot.sh' \
  'service.d/pictorial_home_sync' \
  'pictorialWallpaperCache.dat'
do
  ps -A -o PID=,ARGS= 2>/dev/null | grep -F -- "$pat" | grep -v grep | while read -r pid rest; do
    case "$pid" in *[!0-9]*) ;; *) kill -9 "$pid" 2>/dev/null ;; esac
  done
done

# inotifyd 盯着乐划/本模块路径的
for pid in $(ps -A -o PID=,ARGS= 2>/dev/null | grep inotifyd | grep -v grep | awk '{print $1}'); do
  cmd=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null)
  echo "$cmd" | grep -q pictorial && kill -9 "$pid" 2>/dev/null
done

# pid 文件里的残留
for f in /data/local/tmp/pictorial_home_sync.pid /data/local/tmp/pictorial_home_sync.run; do
  [ -f "$f" ] || continue
  pid=$(cat "$f" 2>/dev/null)
  [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
done

# service.d 旧入口
rm -f /data/adb/service.d/pictorial_home_sync.sh \
      /data/adb/service.d/pictorial_home_sync_handler.sh 2>/dev/null

# 运行时状态（含目录锁）
rm -f /data/local/tmp/pictorial_home_sync.* 2>/dev/null
rm -rf /data/local/tmp/pictorial_home_sync.wm_lock 2>/dev/null
rm -f /data/local/tmp/phs_wall.jpg 2>/dev/null

# 辅助 App（WallpaperManager）
# Magisk 卸载环境 PATH 常不含 pm，必须用绝对路径
PKG=com.local.pictorialhomesync
export PATH=/system/bin:/system/xbin:/product/bin:/vendor/bin:$PATH
if command -v pm >/dev/null 2>&1; then
  pm uninstall --user 0 "$PKG" >/dev/null 2>&1
  pm uninstall "$PKG" >/dev/null 2>&1
fi
/system/bin/pm uninstall --user 0 "$PKG" >/dev/null 2>&1
/system/bin/pm uninstall "$PKG" >/dev/null 2>&1
cmd package uninstall --user 0 "$PKG" >/dev/null 2>&1

# 兜底：直接删包与数据（pm 成功后 ColorOS 有时仍留 data 目录）
rm -rf /data/data/$PKG \
       /data/user/0/$PKG \
       /data/user_de/0/$PKG 2>/dev/null
for d in /data/app/*$PKG* /data/app/*/*$PKG*; do
  [ -e "$d" ] && rm -rf "$d" 2>/dev/null
done
[ -d /data/data/$PKG ] && rm -rf /data/data/$PKG
[ -d /data/user/0/$PKG ] && rm -rf /data/user/0/$PKG

# 勿在此 rm MODDIR，交给 Magisk
exit 0
