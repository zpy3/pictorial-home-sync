#!/system/bin/sh
MODDIR=${0%/*}
MODDIR=$(cd "$MODDIR" 2>/dev/null && pwd) || MODDIR=/data/adb/modules/pictorial_home_sync
. "$MODDIR/common/lib.sh"
export MODDIR

if [ -n "$ASH_STANDALONE" ]; then
  set +o standalone 2>/dev/null
  unset ASH_STANDALONE
fi

STATE_FILE="$MODDIR/config/enabled"
mkdir -p "$MODDIR/config"

if [ "$(cat "$STATE_FILE" 2>/dev/null)" = "1" ]; then
  echo 0 > "$STATE_FILE"
  phs_kill_daemons
  phs_log "disabled by action button"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━"
  echo "  已关闭同步"
  echo "━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "乐划锁屏换图时，仅更换锁屏壁纸"
  echo "（与手机默认行为一致）"
  echo ""
else
  echo 1 > "$STATE_FILE"
  if ! pm path com.heytap.pictorial >/dev/null 2>&1; then
    echo ""
    echo "未检测到「乐划锁屏」应用 (com.heytap.pictorial)"
    echo "本模块仅适用于真我 / OPPO / 一加 ColorOS"
    echo ""
  fi
  rm -f "$PHS_STATE"
  if phs_start_daemon; then
    PHS_FORCE=1 phs_sync_catchup
    phs_log "enabled by action button"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━"
    echo "  已开启同步"
    echo "━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "乐划锁屏换图时，桌面壁纸将同步更换"
    echo ""
  else
    PHS_FORCE=1 phs_sync_catchup
    phs_log "enabled by action (watchdog armed)"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━"
    echo "  已开启同步"
    echo "━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "守护进程由看门狗拉起，约十几秒内生效"
    echo ""
  fi
fi

if [ "$KSU" = "true" -o "$APATCH" = "true" ] && [ "$MMRL" != "true" ]; then
  echo "窗口将在 6 秒后关闭..."
  phs_sleep 6
fi
