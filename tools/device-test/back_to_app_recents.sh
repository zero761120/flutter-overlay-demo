#!/bin/bash
# 「返回 App」不該讓多工畫面多一張卡片的回歸測試：
# 主 App 的卡片被滑掉 → 按「返回 App」→ 返回鍵關掉主 App（卡片留在多工畫面）→ 從桌面圖示再開。
# 「返回 App」建的 task 必須被桌面開的那個取代，不能兩張並存（修正前它的 intent 跟桌面的不同，會留下來）。
#
# 用法：tools/device-test/back_to_app_recents.sh
# 「把卡片滑掉」用 am stack remove 模擬；「從桌面圖示開」用跟桌面相同的 intent 模擬（launch_app）。
set -u
. "$(dirname "$0")/common.sh"

# 球在左邊緣、面板捲到底時「返回 App」的位置。面板加減按鈕、改高度後一定要重量。有副作用的鄰居：
#   上一列「清除錄製檔」不經確認就刪掉錄好的流程 → 結束時會從備份放回去（backup_recordings）
#   上兩列「錄製操作流程」會開始錄製，收尾不會停掉它；存檔時還可能因為數量上限擠掉最舊的錄製檔
#   上四列「螢幕截圖」會存一張截圖到相簿
BACK_TO_APP_BUTTON="347 1870"
TMP_DIR=$(mktemp -d)
RECORDINGS_TAR=$TMP_DIR/recordings.tar
RECORDINGS_BACKED_UP=0

# 錄製檔在 getApplicationDocumentsDirectory()，也就是 App 資料夾下的 app_flutter/flow-*.json
recording_names() {
  adb shell "run-as $PKG sh -c 'ls app_flutter 2>/dev/null'" | tr -d '\r' | grep "^flow-" | LC_ALL=C sort
}
backup_recordings() {
  local names; names=$(recording_names)
  [ -z "$names" ] && return 0
  adb exec-out "run-as $PKG sh -c 'cd app_flutter && tar cf - flow-*.json'" > "$RECORDINGS_TAR"
  # exec-out 沒有結束碼、遠端的 stderr 也會混進來。檔名對得上還不夠：串流在最後一個檔案中間斷掉時
  # tar tf 一樣列得出全部檔名，只有結束碼會是失敗
  local listed
  listed=$(tar tf "$RECORDINGS_TAR" 2>/dev/null) || die "錄製檔備份不完整，不點面板"
  [ "$(echo "$listed" | LC_ALL=C sort)" = "$names" ] || die "錄製檔備份跟手機上的對不起來，不點面板"
  RECORDINGS_BACKED_UP=1
}
# 備份裡有、手機上沒有的錄製檔。比檔名不比數量：點到「錄製操作流程」存了一個新的、又因為數量上限
# 擠掉最舊的一個時，數量不變但少了一個
missing_recordings() {
  comm -23 <(tar tf "$RECORDINGS_TAR" | LC_ALL=C sort) <(recording_names)
}
# 放不回去或沒辦法確認時，備份留在電腦上並以失敗結束
extra_cleanup() {
  if [ "$RECORDINGS_BACKED_UP" = 1 ]; then
    if [ "$(adb get-state 2>/dev/null)" != "device" ]; then
      echo "!! 裝置斷線，沒辦法確認錄製檔還在；備份留在 ${RECORDINGS_TAR}（內容是錄下的操作流程，用完請刪掉）" >&2
      exit 1
    fi
    if [ -n "$(missing_recordings)" ]; then
      # 用 shell -T 而不是 exec-in：shell 協定會等遠端的 tar 跑完並帶回它的結束碼。只看檔名的話，
      # 解到一半失敗（例如空間不夠）留下的截斷檔也會被當成放回去了
      if ! adb shell -T "run-as $PKG sh -c 'cd app_flutter && tar xf -'" < "$RECORDINGS_TAR" \
        || [ -n "$(missing_recordings)" ]; then
        echo "!! 錄製檔放不回去；備份留在 ${RECORDINGS_TAR}（內容是錄下的操作流程，用完請刪掉）" >&2
        exit 1
      fi
      echo "!! 有錄製檔不見了，已從備份放回" >&2
    fi
  fi
  rm -rf "$TMP_DIR"
}

live_task() {
  adb shell dumpsys activity activities | grep -oE "Hist.*$PKG/.MainActivity t[0-9]+" | grep -oE "[0-9]+$" | head -1
}
recent_intent() {
  adb shell dumpsys activity recents | awk -v id="#$1 " 'index($0, id) && /Recent #/ {f=1} f && /^ +intent=/ {print; exit}'
}

back_to_app() {
  require_awake
  set -- $(ball_xy)
  [ "${1:-}" = "0" ] || die "球不在左邊緣：$(overlay_attrs)"
  adb shell input tap $(grab_point $1 $2)
  sleep 1.5
  is_expanded || die "面板沒有展開：$(overlay_attrs)"
  TOUCH_HELD=1
  adb shell input swipe 250 1650 250 1100 400   # 面板捲到底
  TOUCH_HELD=0
  sleep 1
  adb shell input tap $BACK_TO_APP_BUTTON
  sleep 3
}

require_device
backup_recordings
fresh_start
ensure_ball
move_ball_left
launch_app
T=$(live_task); [ -n "$T" ] || die "主 App 沒有在執行"
adb shell am stack remove "$T"                 # 把主 App 的卡片滑掉
sleep 1.5
[ -z "$(live_task)" ] || die "主 App 的 task 沒有被移除"
BEFORE=" $(recent_ids)"                         # 測試開始前就在多工畫面裡的卡片，不算進結果
adb shell input keyevent KEYCODE_HOME
sleep 1.5
back_to_app
A=$(live_task); [ -n "$A" ] || die "按「返回 App」後主 App 沒有開起來"
case "$(recent_intent "$A")" in
  *"act=android.intent.action.MAIN cat=[android.intent.category.LAUNCHER]"*) pass "back-to-app：送出的 intent 跟桌面相同（task ${A}）";;
  *) fail "back-to-app：intent 跟桌面不同：$(recent_intent "$A")";;
esac
require_awake
adb shell input keyevent KEYCODE_BACK            # 主 App 被關掉，卡片留在多工畫面
sleep 1.5
[ -z "$(live_task)" ] || die "返回鍵沒有關掉主 App，這個測試的前提不成立"
case " $(recent_ids)" in
  *" $A "*) ;;
  *) die "返回鍵連卡片一起移除了，這個測試的前提不成立（最後的檢查會不管 intent 都通過）";;
esac
adb shell input keyevent KEYCODE_HOME
sleep 1
launch_app
L=$(live_task); [ -n "$L" ] || die "從桌面再開後主 App 沒有開起來"
NEW=""
for id in $(recent_ids); do
  case "$BEFORE " in *" $id "*) ;; *) NEW="$NEW $id";; esac
done
if [ "${NEW# }" = "$L" ]; then
  pass "back-to-app：多工畫面只多了一張卡片，就是前景那張（$A → ${L}）"
else
  fail "back-to-app：測試新增的卡片是 [${NEW# }]，預期只有前景的 ${L}（「返回 App」建的是 ${A}）"
fi
exit $FAILED
