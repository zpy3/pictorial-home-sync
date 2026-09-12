#!/system/bin/sh
for pid in $(pgrep -f 'pictorial_home_sync' 2>/dev/null); do
  kill -9 "$pid" 2>/dev/null
done
for pid in $(pgrep -f 'pictorialWallpaperCache.dat' 2>/dev/null); do
  kill -9 "$pid" 2>/dev/null
done
rm -f /data/adb/service.d/pictorial_home_sync.sh \
      /data/adb/service.d/pictorial_home_sync_handler.sh \
      /data/local/tmp/pictorial_home_sync.* 2>/dev/null
pm uninstall com.local.pictorialhomesync >/dev/null 2>&1