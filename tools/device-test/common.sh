# 裝置測試腳本的共用設定與函式（由其他腳本 source，不直接執行）。
#
# 座標全部是在參考機上量的：Sony XQ-DQ72（Android 15，1096x2560，density 2.625，Nova 桌面）。
# 換一台螢幕尺寸不同的手機，require_device 會直接中止——照座標點下去會點到別的東西。
#
# adb 會自動讀 ANDROID_SERIAL，所以本檔不帶 -s；接了多台裝置時一定要先設它。

PKG=com.louis.overlay_demo
OVERLAY_SERVICE=$PKG/flutter.overlay.window.flutter_overlay_window.OverlayService
REFERENCE_SIZE=1096x2560
REFERENCE_FONT_SCALE=1.0        # 字型縮放會改變面板按鈕的位置

BALL_PX=126                     # 48dp
BALL_DEFAULT_X=968              # showOverlay 的 startPosition 換成 px
BALL_DEFAULT_Y=1215
LEFT_EDGE_BALL_Y=1837           # move_ball_left 拖到的高度
SHOW_BUTTON="547 959"           # 主 App「顯示懸浮球」
CLOSE_BUTTON_LEFT="256 1105"    # 主 App「關閉懸浮球」的左半邊（右半邊可能被解答小卡蓋住）
X_TARGET="547 2192"             # 底部 X 的中心
EDGE_MARGIN_PX=110              # 42dp：起拖點離螢幕邊至少這麼遠，否則會被返回手勢搶走

die() { echo "!! $*" >&2; exit 1; }

# 共用的前置檢查：一台裝置、尺寸 / 顯示大小 / 字型縮放都跟參考機相同、螢幕亮著、沒鎖。
# 螢幕關著時 input 會全部靜默無效。
require_device() {
  [ "$(adb get-state 2>/dev/null)" = "device" ] || die "找不到裝置（接了多台時要先設 ANDROID_SERIAL）"
  local size font_scale
  size=$(adb shell wm size | sed -n 's/^Physical size: //p' | tr -d '\r')
  [ "$size" = "$REFERENCE_SIZE" ] || die "螢幕是 ${size}，不是參考機的 ${REFERENCE_SIZE}；座標都要重量"
  ! adb shell "wm size; wm density" | grep -q "^Override" || die "改過解析度或顯示大小，座標會對不上"
  font_scale=$(adb shell settings get system font_scale | tr -d '\r')
  [ "$font_scale" = "null" ] && font_scale=1.0
  adb shell run-as $PKG true 2>/dev/null || die "需要可除錯的 debug build（關閉懸浮球、重設狀態都靠 run-as）"
  [ "$font_scale" = "$REFERENCE_FONT_SCALE" ] || die "字型縮放是 ${font_scale}，不是 ${REFERENCE_FONT_SCALE}；面板按鈕的位置會不同"
  require_awake
}

# 判斷「某個東西不見了」之前用：adb 斷線時各種查詢都回空字串，會被當成「不見了」
require_connected() {
  [ "$(adb get-state 2>/dev/null)" = "device" ] || die "裝置斷線了（或接了多台卻沒設 ANDROID_SERIAL），結果不可信"
}

require_awake() {
  adb shell dumpsys power | grep -q "mWakefulness=Awake" || die "螢幕沒亮"
  adb shell dumpsys window | grep -q "isKeyguardShowing=false" || die "螢幕鎖著"
}

# 本 App 最上層那個懸浮窗的 LayoutParams，例如 mAttrs={(968,1215)(126x126)；沒有就是空字串。
# 標題要完全等於套件名：冷啟動時的 "Splash Screen <套件名>" 視窗也是全螢幕，不能被當成展開的面板。
# 底部 X 是另一個同名的懸浮窗（231x231，平常透明），一直在球的下面，所以取第一個（最上層）就是球。
overlay_attrs() {
  adb shell dumpsys window windows | grep -A3 "Window{[0-9a-f]* u0 $PKG}" \
    | grep -o "mAttrs={([0-9-]*,[0-9-]*)([^ ]*)" | head -1
}

# 球的左上角座標 "x y"；目前不是球（展開、沒開）就是空字串。
ball_xy() {
  overlay_attrs | grep "(${BALL_PX}x${BALL_PX})" | sed 's/mAttrs={(\([0-9-]*\),\([0-9-]*\)).*/\1 \2/'
}

is_expanded() { overlay_attrs | grep -q "(fillx"; }

app_pid() { adb shell pidof $PKG | tr -d '\r'; }

# 多工畫面裡本 App 的卡片（task id，空白分隔）
recent_ids() {
  adb shell dumpsys activity recents | grep -oE "Recent #[0-9]+: Task\{[0-9a-f]+ #[0-9]+ type=standard I=$PKG" \
    | grep -oE "#[0-9]+ type" | tr -d '#a-z ' | tr '\n' ' '
}

top_activity() {
  adb shell dumpsys activity activities | grep -m1 -oE "topResumedActivity=ActivityRecord\{[0-9a-f]+ u0 [^ ]+" | awk '{print $3}'
}

# 跟桌面圖示一模一樣的 intent。只用 am start -n 的話 intent 不同，多工畫面會多一張卡片。
# 先回桌面：主 App 已在前景時，確保它真的經過一次 resumed、重新讀懸浮窗狀態與權限。
launch_app() {
  adb shell input keyevent KEYCODE_HOME
  sleep 1
  adb shell am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER \
    -f 0x10200000 -n $PKG/.MainActivity >/dev/null 2>&1   # 已在前景時會印 Warning，呼叫端都會檢查 top_activity
  sleep 4
}

# 從乾淨的狀態開始：關掉懸浮球、殺掉行程（吸附開關、選點、連點目標都存在行程裡，殺掉就回到預設）。
# 無障礙服務開著的話系統會馬上拉回一個空行程，這是正常的。
fresh_start() {
  [ -n "$(overlay_attrs)" ] && close_overlay
  [ -z "$(overlay_attrs)" ] || die "懸浮窗關不掉：$(overlay_attrs)"
  local pid; pid=$(app_pid)
  [ -n "$pid" ] && adb shell run-as $PKG kill -9 $pid
  sleep 2
  [ -z "$pid" ] || [ "$(app_pid)" != "$pid" ] || die "行程沒有被結束（pid ${pid}）"
}

crash_count() { adb logcat -d -b crash | grep -c "Process: $PKG"; }

# 確保懸浮球開著而且是球的形態；開著但不是球（面板、小卡）就先關掉。需要時從主 App 按「顯示懸浮球」。
ensure_ball() {
  [ -n "$(ball_xy)" ] && return 0
  [ -n "$(overlay_attrs)" ] && close_overlay
  # 關不掉的話「顯示懸浮球」的座標會點在自己的面板上
  [ -z "$(overlay_attrs)" ] || die "懸浮窗關不掉：$(overlay_attrs)"
  launch_app
  [ "$(top_activity)" = "$PKG/.MainActivity" ] || die "主 App 不在前景：$(top_activity)"
  require_awake
  adb shell input tap $SHOW_BUTTON
  sleep 3
  [ -n "$(ball_xy)" ] || die "懸浮球沒出現：$(overlay_attrs)"
}

# 跟主 App 的「關閉懸浮球」一樣走 stopService；選點模式蓋滿全螢幕、點不到主 App 時用。
# 不用 onStartCommand 的 IsCloseWindow 分支：服務已經停了的話 startservice 會把它拉起來、進前景，
# 而那個分支在沒有視窗時不會 stopSelf，通知會一直掛著。stopservice 對沒在跑的服務什麼都不做。
close_overlay() {
  adb shell run-as $PKG am stopservice --user 0 -n $OVERLAY_SERVICE >/dev/null 2>&1   # 有沒有關掉看懸浮窗還在不在，不看指令輸出
  sleep 1.5
}

# 起拖點：球貼右邊時抓左側、貼左邊時抓右側，都離螢幕邊 EDGE_MARGIN_PX 以上；不貼邊就抓中心。
grab_point() {
  local x=$1 y=$2 screen_w=${REFERENCE_SIZE%x*}
  if [ "$x" -le 2 ]; then
    echo "$((x + EDGE_MARGIN_PX)) $((y + BALL_PX / 2))"
  elif [ $((x + BALL_PX)) -ge $((screen_w - 2)) ]; then
    echo "$((screen_w - EDGE_MARGIN_PX)) $((y + BALL_PX / 2))"
  else
    echo "$((x + BALL_PX / 2)) $((y + BALL_PX / 2))"
  fi
}

# 把球拖到左邊緣 (0, LEFT_EDGE_BALL_Y)。停住後補一個微動，讓放手時的速度歸零（純吸邊、不甩）。
move_ball_left() {
  local xy gx gy target_finger_y
  xy=$(ball_xy); [ -n "$xy" ] || die "目前不是球：$(overlay_attrs)"
  set -- $xy
  [ "$1" -eq 0 ] && [ "$2" -ge $((LEFT_EDGE_BALL_Y - 5)) ] && [ "$2" -le $((LEFT_EDGE_BALL_Y + 5)) ] && return 0
  set -- $(grab_point $1 $2)
  gx=$1; gy=$2
  # 放手點的手指高度：讓球的上緣落在 LEFT_EDGE_BALL_Y（抓點在球的垂直中心）
  target_finger_y=$((LEFT_EDGE_BALL_Y + BALL_PX / 2))
  require_awake
  TOUCH_HELD=1
  adb shell "input motionevent DOWN $gx $gy; input motionevent MOVE 700 $((target_finger_y - 200)); \
    input motionevent MOVE 400 $((target_finger_y - 50)); input motionevent MOVE 250 $target_finger_y; sleep 0.2; \
    input motionevent MOVE 251 $((target_finger_y + 1)); sleep 0.2; input motionevent UP 251 $((target_finger_y + 1))"
  TOUCH_HELD=0
  sleep 1.5
  xy=$(ball_xy); set -- $xy
  [ -n "$xy" ] && [ "$1" -eq 0 ] || die "球沒有到左邊緣：$(overlay_attrs)"
}

pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; FAILED=1; }
FAILED=0

# 拖曳期間設成 1：手勢中途中止（Ctrl-C 會讓 adb shell 連同裡面的 input 一起結束，UP 送不出去）
# 時，手機上會留著一個按住的觸控
TOUCH_HELD=0

# 不管成功或中途 die，都不要把按住的觸控、面板、小卡或選點模式留在手機上。腳本要加自己的收尾就定義
# extra_cleanup（trap 只能有一個，腳本不要自己 trap EXIT）。
cleanup() {
  if [ "$(adb get-state 2>/dev/null)" = "device" ]; then
    # 用 CANCEL 放開而不是 UP：UP 停在 X 上會把 App 收掉，CANCEL 只會收起 X、球吸邊
    [ "$TOUCH_HELD" = 1 ] && adb shell input motionevent CANCEL 547 1280
    if [ -n "$(overlay_attrs)" ] && [ -z "$(ball_xy)" ]; then
      close_overlay
      [ -z "$(overlay_attrs)" ] || echo "!! 懸浮窗關不掉，請手動關閉：$(overlay_attrs)" >&2
    fi
  fi
  if declare -F extra_cleanup >/dev/null; then extra_cleanup; fi
}
trap cleanup EXIT

# 打錯情境名稱時直接中止，不要變成「什麼都沒跑、結果是成功」
check_cases() {
  local c
  for c in "$@"; do declare -F "case_$c" >/dev/null || die "沒有這個情境：$c"; done
}
