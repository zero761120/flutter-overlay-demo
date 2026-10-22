#!/bin/bash
# 重開懸浮球時有沒有重設回球的回歸測試，兩個情境：
#   card   解答小卡開著時從主 App 關閉、再重開 → 球的視窗裡應該畫著球（修正前：擠著小卡、OVERFLOWED）
#   picker 選點模式中關閉、再重開、點球 → 應該打開面板（修正前：直接進選點模式）
#
# 用法：tools/device-test/reopen_reset.sh [card] [picker]（不給就兩個都跑）
# 畫面內容用截圖裡「球的藍色」像素數判斷（count_blue.py），門檻是在參考機上量的。
# 「解題」在沒有盤面的畫面會給出錯誤小卡，一樣是小卡形態，所以不需要開遊戲。
set -u
HERE=$(dirname "$0")
. "$HERE/common.sh"
CASES=${*:-card picker}
TMP_DIR=$(mktemp -d)
SHOT=$TMP_DIR/shot.png
extra_cleanup() { rm -rf "$TMP_DIR"; }

# 球在預設位置 (968,1215) 時，面板的按鈕座標
SOLVE_BUTTON="746 1176"
PICK_BUTTON="746 752"
SOLVE_BUTTON_REGION="480 1150 520 50"   # 「解題」實心藍按鈕所在的範圍
BLANK_SPOT="150 2300"                    # 面板外的空白處，點了會收合
# 參考機實測：球的位置 球 11793 / 面板 1278 / 沒懸浮窗 0；「解題」範圍 面板 22872 / 選點模式 0 / 沒懸浮窗 0
BALL_BLUE_MIN=8000
PANEL_BLUE_MIN=10000

blue_in() { adb exec-out screencap -p > "$SHOT"; python3 -I "$HERE/count_blue.py" "$SHOT" "$@"; }

ball_at_default() {
  if [ "$(ball_xy)" != "$BALL_DEFAULT_X $BALL_DEFAULT_Y" ]; then
    [ -n "$(overlay_attrs)" ] && close_overlay
    ensure_ball
  fi
  [ "$(ball_xy)" = "$BALL_DEFAULT_X $BALL_DEFAULT_Y" ] || die "球不在預設位置：$(overlay_attrs)"
}

open_panel() {
  require_awake
  adb shell input tap $(grab_point $BALL_DEFAULT_X $BALL_DEFAULT_Y)
  sleep 1.5
  is_expanded || die "面板沒有展開：$(overlay_attrs)"
}

# 球本來就在預設位置時 ball_at_default 不會開主 App。兩個情境都要主 App 在底下：card 要點它的
# 「關閉懸浮球」，picker 要靠它在「解題」範圍是空白，來分辨選點模式與面板。
host_app_behind() {
  launch_app
  [ "$(top_activity)" = "$PKG/.MainActivity" ] || die "主 App 不在前景：$(top_activity)"
}

case_card() {
  ball_at_default
  host_app_behind
  open_panel
  adb shell input tap $SOLVE_BUTTON
  sleep 2.5
  local attrs; attrs=$(overlay_attrs)
  case "$attrs" in *"(${BALL_PX}x${BALL_PX})"*|*fillx*|"") die "沒有出現解答小卡：$attrs";; esac
  [ "$(top_activity)" = "$PKG/.MainActivity" ] || die "主 App 不在前景，點下去會點到別的東西：$(top_activity)"
  adb shell input tap $CLOSE_BUTTON_LEFT
  sleep 1.5
  [ -z "$(overlay_attrs)" ] || die "懸浮球沒有關掉：$(overlay_attrs)"
  ensure_ball
  local n; n=$(blue_in $BALL_DEFAULT_X $BALL_DEFAULT_Y $BALL_PX $BALL_PX)
  if [ "$n" -ge $BALL_BLUE_MIN ]; then
    pass "card：重開後是一顆球（球視窗內藍色像素 ${n}）"
  else
    fail "card：重開後球的視窗裡不是球（藍色像素 $n < ${BALL_BLUE_MIN}）"
  fi
}

case_picker() {
  ball_at_default
  host_app_behind
  open_panel
  adb shell input tap $PICK_BUTTON
  sleep 1.5
  # 面板跟選點模式都是全螢幕（fillx），用「解題」按鈕的藍色還在不在分辨：選點模式是透明的一層，
  # 只在中間顯示提示，那個範圍看到的是底下主 App 的空白處
  is_expanded && [ "$(blue_in $SOLVE_BUTTON_REGION)" -lt $PANEL_BLUE_MIN ] \
    || die "沒有進入選點模式：$(overlay_attrs)"
  close_overlay
  [ -z "$(overlay_attrs)" ] || die "懸浮球沒有關掉：$(overlay_attrs)"
  ensure_ball
  open_panel
  local n; n=$(blue_in $SOLVE_BUTTON_REGION)
  if [ "$n" -ge $PANEL_BLUE_MIN ]; then
    adb shell input tap $BLANK_SPOT
    sleep 1.5
    pass "picker：重開後點球打開的是面板（「解題」按鈕藍色像素 ${n}）"
  else
    # 還在選點模式的話點空白處會設下目標、全螢幕的層也收不掉，直接關掉
    close_overlay
    fail "picker：重開後點球沒有打開面板，可能還在選點模式（藍色像素 $n < ${PANEL_BLUE_MIN}）"
  fi
}

check_cases $CASES
require_device
fresh_start
for c in $CASES; do "case_$c"; done
exit $FAILED
