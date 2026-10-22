#!/bin/bash
# 授權流程的回歸測試（requestPermission 會不會回傳）：
# 收回懸浮窗權限 → 主 App 按「顯示懸浮球」→ 跳到系統授權頁 → 給回權限、按返回 → 懸浮球應自己出現。
# 修正前懸浮球不會出現，要再按一次（_show 一直卡在等 requestPermission）。
#
# 用法：tools/device-test/permission_flow.sh
# 不管成功、失敗或中途中止，結束時都會把權限恢復成測試前的值。
set -u
. "$(dirname "$0")/common.sh"

require_device
# 沒設過時 appops get 印 "No operations."，對應的模式是 default；讀不到（斷線）就是空字串
current_mode() {
  local out; out=$(adb shell appops get $PKG SYSTEM_ALERT_WINDOW 2>/dev/null)
  case "$out" in
    *"No operations"*) echo default;;
    *) echo "$out" | sed -n 's/^SYSTEM_ALERT_WINDOW: \([a-z_]*\).*/\1/p';;
  esac
}
PREVIOUS_MODE=$(current_mode)
[ -n "$PREVIOUS_MODE" ] || die "讀不到目前的懸浮窗權限"
# 恢復失敗（例如中途拔線）要大聲說，不然權限會一直停在 deny
extra_cleanup() {
  # 原本不是 allow 的話，恢復之後球的視窗會被藏起來、只剩常駐通知，所以先關掉
  if [ "$PREVIOUS_MODE" != "allow" ] && [ -n "$(overlay_attrs)" ]; then close_overlay; fi
  adb shell appops set $PKG SYSTEM_ALERT_WINDOW "$PREVIOUS_MODE"
  if [ "$(current_mode)" != "$PREVIOUS_MODE" ]; then
    echo "!! 懸浮窗權限沒有恢復，請手動執行：adb shell appops set $PKG SYSTEM_ALERT_WINDOW $PREVIOUS_MODE" >&2
    exit 1
  fi
}

fresh_start
adb shell appops set $PKG SYSTEM_ALERT_WINDOW deny
launch_app
[ "$(top_activity)" = "$PKG/.MainActivity" ] || die "主 App 不在前景：$(top_activity)"
require_awake
adb shell input tap $SHOW_BUTTON
sleep 2.5
case "$(top_activity)" in
  com.android.settings/*) ;;
  *) die "沒有跳到系統授權頁：$(top_activity)";;
esac
adb shell appops set $PKG SYSTEM_ALERT_WINDOW allow   # 等同使用者在授權頁打開開關
sleep 1
adb shell input keyevent KEYCODE_BACK
sleep 3
if [ -n "$(ball_xy)" ]; then
  pass "permission：給完權限按返回，懸浮球自己出現（$(ball_xy)）"
else
  fail "permission：按返回後沒有懸浮球（$(overlay_attrs)），top=$(top_activity)"
fi
exit $FAILED
