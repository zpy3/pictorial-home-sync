#!/system/bin/sh
SKIPUNMOUNT=1
ui_print "- 乐划锁屏桌面同步 v1.0.3"
ui_print "- 适用于真我/OPPO/一加 (com.heytap.pictorial)"

# permissions
set_perm_recursive $MODPATH 0 0 0755 0644
set_perm $MODPATH/action.sh 0 0 0755
set_perm $MODPATH/service.sh 0 0 0755
set_perm $MODPATH/uninstall.sh 0 0 0755
set_perm $MODPATH/common/handler.sh 0 0 0755
set_perm $MODPATH/common/daemon.sh 0 0 0755
set_perm $MODPATH/common/lib.sh 0 0 0755
set_perm $MODPATH/common/watchdog.sh 0 0 0755
set_perm $MODPATH/common/pictorial-home-sync.apk 0 0 0644
set_perm $MODPATH/action.png 0 0 0644
mkdir -p $MODPATH/config
[ -f $MODPATH/config/enabled ] || echo 1 > $MODPATH/config/enabled
set_perm $MODPATH/config/enabled 0 0 0644

# remove legacy service.d scripts from earlier manual install
rm -f /data/adb/service.d/pictorial_home_sync.sh \
      /data/adb/service.d/pictorial_home_sync_handler.sh 2>/dev/null

# install helper apk
ui_print "- 安装壁纸同步组件"
if [ -f "$MODPATH/common/pictorial-home-sync.apk" ]; then
  if pm install -r -g "$MODPATH/common/pictorial-home-sync.apk" >/dev/null 2>&1; then
    ui_print "  APK 安装成功"
  elif pm install -r "$MODPATH/common/pictorial-home-sync.apk" >/dev/null 2>&1; then
    ui_print "  APK 安装成功"
  else
    ui_print "  ! APK 将在首次开机由 service 重试安装"
  fi
else
  ui_print "  ! 未找到 APK（zip 目录结构异常）"
fi

ui_print "- 默认已开启同步"
ui_print "- 在模块列表左下角「操作」可开关"
ui_print "- 重启后生效（也可点操作按钮立即生效）"
