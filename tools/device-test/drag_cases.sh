#!/bin/bash
# 拖曳與拖去 X 的回歸測試。每個情境印 PASS / FAIL。
#
# 用法：tools/device-test/drag_cases.sh [--record <目錄>] [情境 ...]
#   情境：unstick snap escape drop fling（不給就全跑；drop / fling 會把 App 收掉，放最後）
#   --record：每個情境錄一支影片到 <目錄>/<情境>.mp4，可再用 track_ball.py 逐幀量球的位置
#
# 合成的 input motionevent 停住時不會像真手指一樣持續送微小移動，而「橫向速度太快不吸」要等下一個
# 移動事件才會重新判斷——所以拖進 X 之後都會停一下再補一個微動。
set -u
. "$(dirname "$0")/common.sh"

ALL_CASES="unstick snap escape drop fling"
RECORD_DIR=""
if [ "${1:-}" = "--record" ]; then
  [ $# -ge 2 ] || die "--record 後面要接錄影存放的目錄"
  # 情境名稱不能當目錄：--record snap 會變成「全部情境都跑」，連 drop、fling 都會把 App 收掉
  case " $ALL_CASES " in *" $2 "*) die "--record 後面要接目錄，不是情境名稱：$2";; esac
  RECORD_DIR=$2; shift 2
  mkdir -p "$RECORD_DIR" || die "建不了目錄 $RECORD_DIR"
fi
CASES=${*:-$ALL_CASES}

record_start() {
  [ -z "$RECORD_DIR" ] && return 0
  adb shell rm -f /sdcard/drag_case.mp4
  adb shell screenrecord --bit-rate 20000000 /sdcard/drag_case.mp4 &
  sleep 1.5
}
record_stop() {
  [ -z "$RECORD_DIR" ] && return 0
  sleep 1
  adb shell pkill -INT screenrecord
  sleep 2
  adb pull /sdcard/drag_case.mp4 "$RECORD_DIR/$1.mp4" >/dev/null
  adb shell rm -f /sdcard/drag_case.mp4
}
# 中途 die 時錄影還在背景跑（adb 的 screenrecord 沒有任何畫面提示），要停掉、刪掉手機上的檔
extra_cleanup() {
  [ -z "$RECORD_DIR" ] && return 0
  adb shell pkill -INT screenrecord
  sleep 1
  adb shell rm -f /sdcard/drag_case.mp4
}

# 手指從 (gx,gy) 分 8 步走到 (620,1930)（還在磁吸範圍外），再進到 (590,2080)，停一下補微動
approach_x() {
  local gx=$1 gy=$2 cmd="input motionevent DOWN $1 $2" i
  for i in 1 2 3 4 5 6 7 8; do
    cmd="$cmd; input motionevent MOVE $((gx + (620 - gx) * i / 8)) $((gy + (1930 - gy) * i / 8))"
  done
  TOUCH_HELD=1
  adb shell "$cmd; input motionevent MOVE 590 2080; sleep 0.1; input motionevent MOVE 591 2081"
}

case_unstick() {
  ensure_ball; require_awake
  local pid; pid=$(app_pid)
  set -- $(ball_xy); set -- $(grab_point $1 $2)
  approach_x $1 $2
  sleep 0.6
  # 被吸住時球心對準 X：視窗左上角 = X 中心 - 球半徑
  set -- $(ball_xy) ; local sx=${1:-} sy=${2:-}
  local cmd="input motionevent MOVE 591 2081" i
  for i in 1 2 3 4 5 6; do cmd="$cmd; input motionevent MOVE $((591 - 50 * i)) $((2081 - 30 * i))"; done
  adb shell "$cmd; sleep 0.8; input motionevent UP 290 1900"
  TOUCH_HELD=0
  sleep 1.5
  set -- $X_TARGET
  if [ $((sx - ($1 - BALL_PX / 2))) -ge -5 ] && [ $((sx - ($1 - BALL_PX / 2))) -le 5 ] \
    && [ $((sy - ($2 - BALL_PX / 2))) -ge -5 ] && [ $((sy - ($2 - BALL_PX / 2))) -le 5 ]; then
    pass "unstick：拖進範圍時球被吸到 X 中心（$sx,${sy}）"
  else
    fail "unstick：拖進範圍時球不在 X 中心（$sx,${sy}）"
  fi
  set -- $(ball_xy)
  if [ "${1:-}" = "0" ] && [ "$(app_pid)" = "$pid" ]; then
    pass "unstick：拉出後放手吸回左邊緣（$1,$2），App 還在"
  else
    fail "unstick：放手後 $(overlay_attrs)，pid $pid → $(app_pid)"
  fi
}

case_snap() {
  ensure_ball; require_awake
  set -- $(ball_xy); set -- $(grab_point $1 $2)
  local gx=$1 gy=$2 cmd="input motionevent DOWN $1 $2" i
  for i in 1 2 3 4 5 6 7 8; do cmd="$cmd; input motionevent MOVE $((gx + (350 - gx) * i / 8)) $((gy + (1800 - gy) * i / 8))"; done
  TOUCH_HELD=1
  adb shell "$cmd; sleep 0.15; input motionevent MOVE 351 1801; sleep 0.1; input motionevent UP 351 1801"
  TOUCH_HELD=0
  sleep 1.5
  set -- $(ball_xy)
  if [ "${1:-}" = "0" ] && [ "${2:-0}" -ge 1730 ] && [ "${2:-0}" -le 1745 ]; then
    pass "snap：在左半邊放手，吸回左邊緣、高度不變（$1,$2）"
  else
    fail "snap：放手後 $(overlay_attrs)"
  fi
}

case_escape() {
  ensure_ball; require_awake
  set -- $(ball_xy); local bx=$1
  set -- $(grab_point $1 $2); local gx=$1 gy=$2 ex expect
  # 停在同一半邊，但朝另一邊快速甩：照 AOSP ESCAPE_VELOCITY 應該去另一邊
  if [ "$bx" -lt 548 ]; then ex=450; expect=right; else ex=646; expect=left; fi
  TOUCH_HELD=1
  adb shell input swipe $gx $gy $ex $gy 120
  TOUCH_HELD=0
  sleep 1.5
  set -- $(ball_xy)
  if { [ $expect = right ] && [ "${1:-0}" -ge 960 ]; } || { [ $expect = left ] && [ "${1:-1}" = "0" ]; }; then
    pass "escape：往另一邊甩，飛到 $expect 邊緣（$1,$2）"
  else
    fail "escape：預期 $expect 邊緣，實際 $(overlay_attrs)"
  fi
}

# 丟掉之後的判定：懸浮窗沒了，行程換掉（無障礙會讓系統重拉一個空行程，所以 pid 可能還有、但不同），
# 而且多工畫面沒有卡片。crash、ANR、被系統殺掉也會讓懸浮窗消失、pid 換掉，但只有 exitApp 會移除卡片。
check_dismissed() {
  local name=$1 pid=$2 now cards
  sleep 2.5
  require_connected
  now=$(app_pid); cards=$(recent_ids)
  require_connected
  if [ -z "$(overlay_attrs)" ] && [ "$now" != "$pid" ] && [ -z "$cards" ] && [ "$(crash_count)" -eq "$CASE_CRASHES" ]; then
    pass "${name}：App 已收掉，卡片也移除了（pid $pid → ${now:-無}）"
  else
    fail "${name}：懸浮窗 [$(overlay_attrs)]，pid $pid → ${now:-無}，卡片 [$cards]"
  fi
}

case_drop() {
  ensure_ball; require_awake
  local pid; pid=$(app_pid)
  set -- $(ball_xy); set -- $(grab_point $1 $2)
  approach_x $1 $2
  sleep 0.6
  adb shell input motionevent UP 591 2081
  TOUCH_HELD=0
  check_dismissed drop "$pid"
}

case_fling() {
  # 從預設位置甩才有足夠的垂直距離達到甩入門檻；球不在那裡就關掉重開
  if [ "$(ball_xy)" != "$BALL_DEFAULT_X $BALL_DEFAULT_Y" ]; then
    [ -n "$(overlay_attrs)" ] && close_overlay
    ensure_ball
  fi
  [ "$(ball_xy)" = "$BALL_DEFAULT_X $BALL_DEFAULT_Y" ] || die "球不在預設位置：$(overlay_attrs)"
  require_awake
  local pid; pid=$(app_pid)
  set -- $(grab_point $BALL_DEFAULT_X $BALL_DEFAULT_Y)
  TOUCH_HELD=1
  adb shell input swipe $1 $2 $(($1 - 225)) $(($2 + 372)) 80
  TOUCH_HELD=0
  check_dismissed fling "$pid"
}

check_cases $CASES
require_device
fresh_start   # 吸附開關若被關掉，unstick / snap / escape 會假失敗
for c in $CASES; do
  CASE_CRASHES=$(crash_count)
  record_start
  "case_$c"
  record_stop "$c"
  [ "$(crash_count)" -gt "$CASE_CRASHES" ] && fail "${c}：期間 App crash 了（adb logcat -d -b crash 看內容）"
done
exit $FAILED
