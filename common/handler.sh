#!/system/bin/sh
# inotifyd callback — $1=events
HERE=$(readlink -f "$0" 2>/dev/null || echo "$0")
COMMON=$(dirname "$HERE")
MODDIR=$(dirname "$COMMON")
. "$MODDIR/common/lib.sh"
export MODDIR
[ "$(cat "$MODDIR/config/enabled" 2>/dev/null)" = "1" ] || exit 0
phs_sync_catchup