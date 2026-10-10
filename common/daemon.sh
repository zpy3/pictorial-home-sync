#!/system/bin/sh
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
phs_log "daemon.sh start mod=$MODDIR pid=$$ ppid=$PPID (uri-only)"

rm -rf "$PHS_WM_LOCK" 2>/dev/null
rm -f "$PHS_FROZEN" "$PHS_PREFER_NEXT" "$PHS_PREFER_SHOW"
(phs_sync_catchup) &

HANDLER="$MODDIR/common/handler.sh"
(
  while true; do
    [ "$(cat "$MODDIR/config/enabled" 2>/dev/null)" = "1" ] || exit 0
    if [ -e "$PHS_SRC_CACHE" ]; then
      /system/bin/inotifyd "$HANDLER" "$PHS_SRC_CACHE:wcmn"
      phs_sleep 0.1
    else
      phs_sleep 2
    fi
  done
) &

last_uri=$(phs_show_stat_cookie)
last_on=0
phs_screen_on && last_on=1
on_chase=0

# 只跟 pictorial_file_uri 当前图。
# 息屏换图：灭屏时 URI 已换成新图 → 立刻同步，解锁无动画。
# 禁止再用 next= 预铺（实测 next 常陈旧，会盖错再被亮屏纠正 → 动画）。
while true; do
  [ "$(cat "$MODDIR/config/enabled" 2>/dev/null)" = "1" ] || {
    phs_log "daemon exit: disabled"
    exit 0
  }

  on=0
  phs_screen_on && on=1
  uri_cookie=$(phs_show_stat_cookie)
  need=0

  if [ "$on" = "0" ]; then
    if [ "$last_on" = "1" ]; then
      phs_log "screen off → sync uri"
      phs_warm_helper
      need=1
      on_chase=0
    fi
  else
    if [ "$last_on" = "0" ]; then
      phs_log "screen on → sync uri"
      need=1
      on_chase=10
    fi
  fi

  if [ "$uri_cookie" != "$last_uri" ]; then
    base=$(phs_uri_basename "$(phs_settings_get "$PHS_SET_FILE_URI")")
    phs_log "uri changed → $base"
    last_uri=$uri_cookie
    need=1
    [ "$on" = "1" ] && on_chase=6
  fi

  if [ "$on" = "1" ] && [ "$on_chase" -gt 0 ]; then
    on_chase=$((on_chase - 1))
    # chase 期间每拍检查 cookie，变了上面已处理；结束再兜底跟一次
    if [ "$on_chase" -eq 0 ]; then
      need=1
    fi
  fi

  last_on=$on

  if [ "$need" = "1" ] || [ -f "$PHS_PENDING" ] || [ -f "$PHS_NEED_WM" ]; then
    rm -f "$PHS_PREFER_NEXT"
    phs_sync_catchup
    phs_set_hold_from_fp
    last_uri=$(phs_show_stat_cookie)
    # 若同步完 URI 又变了（灭屏瞬间写入），下轮立刻再跟
  fi

  phs_sleep 0.08
done
