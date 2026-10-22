# flutter-overlay-demo

**繁體中文** · [English](README.en.md)

Android 懸浮球（類 AssistiveTouch）的 Flutter 實作驗證。個人自用，非產品。

球可拖曳、放手吸附邊緣（可開關），拖曳時底部會出現 X，丟進去（或往它甩）就關閉整個 App。
點一下球展開選單。選單提供：設定連點目標、開始／停止連點
（300ms 間隔）、螢幕截圖、**解題：貓咪在哪裡**（MeowDoku）、**錄製操作流程**、清除錄製檔、
返回 App。懸浮層做過的動作會回報
給主 App 列成紀錄。主題與語系跟隨系統（日／夜、中／英），配色沿用一套慣用的藍色主題。

**僅 Android**——iOS 沒有任何公開 API 能畫到其他 App 之上。

## 需要兩道獨立權限

| 權限 | 用途 | 取得方式 |
|---|---|---|
| `SYSTEM_ALERT_WINDOW` | 懸浮窗本體 | 系統設定頁手動授權，**沒有 runtime dialog** |
| 無障礙服務 | 模擬點擊 / 截圖 / 錄製 | 設定 → 協助工具 手動啟用 |

## 建置

```bash
fvm flutter pub get
fvm flutter build apk --debug
```

## 拖去 X 關閉

手感照系統的通知泡泡做（AOSP WM Shell 的 `DismissView` + `MagnetizedObject`）：

- 開始拖曳時，底部中間淡入一個 X（白色圓框、透明底）
- 手指進到 X 周圍 64dp 內：球帶著手指當下的速度，用彈簧滑進中心並震一下，圓框擴大圍住球；
  拉出範圍時，球用彈簧追回手指
- 在 X 上放手，或往 X 用力甩（向下夠快，且甩的延伸線落在以 X 為中心、三倍 X 寬的範圍內）：球縮小消失，接著關掉
  懸浮窗、前景通知與主 App（最近任務也一併移除），最後結束行程。錄製中的步驟會先落檔
- 沒丟進 X 就放手（吸附開著時）：球用彈簧吸回最近的邊；朝另一邊甩得夠快就去另一邊

彈簧與門檻都抄自 AOSP（android13）：吸入 stiffness 1500／臨界阻尼、追手指 12000／0.85、吸邊
700／0.85。原本的速度門檻是 px/s，這裡依實機密度換成 dp/s。

無障礙服務**不會**跟著關掉（關掉的話，下次要再到設定頁授權）。只要它還開著，系統就會立刻再拉起
一個行程來綁定它：那個行程沒有 Flutter 引擎，沒人監聽時也不處理任何事件（見下方的修正），實測約
28MB PSS。

系統對不可觸控的覆蓋層，強制最多 0.8 的不透明度，所以 X 的白色會略帶灰。

**自動化測試時注意**：起拖點要離螢幕邊至少 42dp（見「已知問題」的返回手勢）。另外，`adb shell
input motionevent` 停住時不會像真手指一樣持續送出微小移動，而 AOSP「橫向速度太快不吸」的規則要等
下一個移動事件才會重新判斷，所以「拖進 X 放手」會假失敗——停住後要補一個微動。

## 錄製操作流程

訂閱無障礙事件、記錄使用者在其他 App 的操作，落成 JSON。用途是把「爬得到什麼」從猜測
變成看得到——無障礙露出多少**完全取決於目標 App 怎麼寫的**（有沒有設 id、有沒有
`contentDescription`、用標準元件還是自繪；Flutter App 只給 Semantics、WebView 要對方啟用），
沒有規格可查，錄一次比讀十篇文件有用。

用法：面板 →「錄製操作流程」（面板自動收合）→ 去目標 App 操作 → 回來停止，或直接從主 App
關閉懸浮球（會自動停止並落檔）。主畫面的「錄製檔」可以看清單 → 步驟（預設只列點擊）→
原始 JSON（折疊、截斷顯示）。

步驟的顯示名稱優先取 `contentDescription` 而非 `text`：實測計算機那些按鈕的 `text` 全是
null，只有 `contentDescription` 有值——不補這個欄位，整份紀錄會是一排空白。

檔案在 app-private 的內部儲存，只留最近 5 份。debug build 要取出：

```bash
adb exec-out run-as com.louis.overlay_demo ls app_flutter/
adb exec-out run-as com.louis.overlay_demo cat app_flutter/flow-<timestamp>.json > flow.json
```

## 解題：貓咪在哪裡（MeowDoku）

規則：N×N 盤面分成 N 個色塊，每行、每列、每個色塊各放一隻貓，且任兩隻不能相鄰——
**含斜角**（只算上下左右的話，「每行每列各一隻」本身就保證不相鄰，那條規則就沒有意義）。

遊戲是 Godot 引擎自繪的，無障礙樹裡只有一個空容器、讀不到任何格子，只能看像素：

1. 面板 →「解題：貓咪在哪裡」。懸浮層先清成透明，否則面板會壓在盤面上被一起拍進去
2. 用無障礙服務的 `takeScreenshot`（Android 11+）直接拿像素：**不需要 MediaProjection 的
   授權彈窗、不進相簿、不落檔**
3. 找盤面：把「每列 / 每欄有幾個有色像素」畫成投影，盤面會是一串等寬等距的高原；
   N 由畫面量出，8～12 格的關卡都適用
4. 讀色塊：每格沿外圈取 8 點、濾掉白（叉、貓臉）與黑（貓毛）再投票——玩到一半滿版打叉、
   開了圖案模式都讀得出來
5. 逐行回溯解題。**找到第二組解就當成讀錯**：某格被歸到隔壁色塊時，顏色種類數不變，前面
   的檢查擋不到；實測第 10 關 162 種單格誤讀中，42 種只取第一組會是錯答案，而它們全都
   不只一組解
6. 視窗縮成小卡，擺在盤面正下方（放不下才放上方）、跟球同一側；可拖動，點一下收回成球

實機（Android 15）驗證：每日挑戰 12×12 全新盤面、第 1642 關 10×10 玩到剩一隻（一般與
圖案模式），答案都與遊戲內正解一致；遊戲首頁正確回報找不到盤面。

辨識是照這款遊戲的畫面風格調的（淺色底、白色間隔、純色格子），換了配色或別款遊戲不保證。
讀不出來時小卡會寫出原因（找不到盤面、行列數不符、色塊數不符、無解、不只一組解），不會
硬給一個答案。

**測試時注意**：用 uiautomator 讀畫面元素（包括 mobile-mcp 的元素清單）會連上一個
UiAutomation，而 Android 在它連著的期間**暫停所有無障礙服務**——設定頁仍顯示「已啟用」，
截圖卻回「服務尚未就緒」。mobile-mcp 會在裝置上留下 `com.mobilenext.mobilecli.DeviceServer`，
閒置 30 分鐘才結束；`adb shell kill` 掉它，服務一兩秒內就自己重新綁定。改用
`adb shell input` + `adb exec-out screencap` 就不會碰到。要確認服務有沒有綁上，看
`dumpsys accessibility` 的 Bound services：這份清單會跨行，只 grep 一行會把「有綁上」誤判成「沒綁上」。

## 使用須知

這個工具會請求兩道高權限（懸浮窗、無障礙服務），能模擬觸控、截取畫面，**並能記錄其他
App 的畫面文字**。這些能力本身是 Android 官方 API、用途中性，但**怎麼用是使用者的責任**：
用在自己的裝置與帳號上沒有問題；用來干擾他人系統、繞過保護措施，或違反某個服務的使用
條款，後果自負。

隱私上做了幾件事：擷取路徑全數跳過 `isPassword()` 的節點；錄製檔放 app-private 內部儲存
而非外部儲存；`allowBackup` 關閉——Auto Backup 的預設範圍**正是**內部儲存，不關等於前門
關了後門開著；事件 payload 走 in-process 佇列而非系統廣播，不讓其他 App 有機會被動接收；
解題的截圖只在記憶體裡停留到讀完盤面，留下的只有色塊編號與顏色，不落檔。

作者不對任何使用後果負責（見 `LICENSE`）。

## 授權

本專案採 MIT（見 `LICENSE`）。

`packages/` 下的兩個套件是第三方程式的**修改版**，原作者 Iheb Briki，原授權 MIT，
各自的 `LICENSE` 檔已完整保留。修改處在原始碼中以 `LOCAL PATCH` 註解標出，內容與理由
見下一節。修正的部分都是上游的真實缺陷或沒處理到的限制；另有幾項新增功能（截圖回傳像素、
拖去 X 關閉、原生吸邊、跟桌面一致的「返回 App」），也標在下一節。

`flutter_accessibility_service` 的部分已回報：

- [#46](https://github.com/X-SLAYER/flutter_accessibility_service/issues/46) — `onServiceConnected` 的 crash loop
- [#47](https://github.com/X-SLAYER/flutter_accessibility_service/issues/47) — 五個擷取缺陷，附帶兩個未主張解法的架構問題

這個套件之後找到的兩項（`onStartCommand` 的 crash、沒人監聽時照樣處理事件）尚未回報：上面兩張到
2026-10-22 都沒有回應，上游自 2026-06 後也沒有新的 push。

`flutter_overlay_window` 原本都沒報：當時上游最後一次發布是 2025-04，已停滯一年半。上游後來在
2026-10 恢復更新（1.0.0／1.0.1，main 之後又合併了一批）。2026-10-22 比對 main（`e3c3549`）：
拖曳門檻改用 touch slop、sub-pixel 拖曳、拖去 X（簡化版）、`getScreenSize`、拖完不算點擊、只在真的
拖過才吸邊，上游已修或有對應做法；`onStartCommand` 的 crash、訊息路由、轉向後跑出畫面、重開收不到
resumed、resize 高度判斷式則都還沒修。這裡仍用 0.5.0 的修改版。

- [#205](https://github.com/X-SLAYER/flutter_overlay_window/issues/205) — `onStartCommand` 的
  crash（先前回報的 #177／#181／#186 已被關閉，但程式碼沒改）

## 本地修正的第三方套件

兩個套件各 vendor 一份修正版（`packages/`，走 `dependency_overrides`）。多數問題同一種
性質：**上游假設自己只會被註冊在一個 engine 上**，而這個 app 有兩個（主 App 與懸浮層）。

### `flutter_overlay_window`（0.5.0 的複本）

**訊息路由** — `WindowSetup.messenger` 是靜態欄位，卻在 `onAttachedToEngine` 指派。外掛在
兩個 engine 各註冊一次，後註冊的（懸浮層）覆蓋前者，於是 `OverlayService` 把懸浮層的
`shareData()` **轉回懸浮層自己**，主 App 永遠收不到。改成在 `onAttachedToActivity` 指派——
只有主 engine 會有 Activity，那是唯一能分辨兩者的地方。

**轉向** — 懸浮窗不是 Activity，畫面轉了它仍留在原地。實測直向拖到 `y=2084` 後轉橫向，
可視高度只剩 1033，球整顆在畫面外、點不到。補上 `onConfigurationChanged` 夾回可視範圍。
Dart 的 `didChangeMetrics` **不是可用的掛鉤點**：球的視窗是固定 48dp，轉向時它自己的
viewport metrics 不變，callback 根本不會觸發。

**轉向後的螢幕尺寸** — 懸浮層引擎掛在 Service 底下、沒有 Activity，而 Flutter embedding
只在找得到 Activity 時才把螢幕尺寸送進引擎（Flutter 3.38.10 的
`ViewUtils.calculateMaximumDisplayMetrics` 反組譯確認），所以懸浮層的 `display.size` 停在
引擎建立當下的方向。實測橫向建立、轉回直向後，吸右門檻（球心過半寬）變成 487dp，直向卻
最寬只有 417dp，往右拖一律吸回左邊。補上 `getScreenSize`（`getRealMetrics`，與
`display.size` 同語意），Dart 在每個要用到尺寸的動作開頭現問一次。放手吸邊後來改由原生做，
直接用原生量到的尺寸；Dart 這邊現在只在展開／收合時用到。

**服務被殺後以 null intent 重啟** — `onStartCommand` 回 `START_STICKY`，卻無條件讀 intent。
懸浮窗開著時行程若被殺，系統會用 null intent 重啟服務，結果 NPE。就算重啟成功也救不回懸浮窗
（位置與尺寸都在那個已經沒了的 intent 裡），所以全部改成 `START_NOT_STICKY`，再補上 null 防護。

**新增：`openHostApp`（「返回 App」改由原生發 intent）** — 原本用 android_intent_plus 自己組，
action 是字面的 `action_main`（外掛不會轉成 `ACTION_MAIN`），而且外掛只要指定元件就一定帶 package。
Flutter 範本的 `taskAffinity=""` 讓最近任務只會合併「intent 完全相同（filterEquals）」的兩筆，
跟桌面圖示的 intent 永遠不同。實測：主 App 被返回鍵關掉後（懸浮球讓行程一直活著，task 留在最近
任務裡），桌面圖示與「返回 App」交替著開，多工畫面就出現兩張 overlay_demo 卡片（只用其中一種開
不會）。現在照桌面的寫法發：
`Intent.makeMainActivity(元件)`（MAIN + LAUNCHER、只帶元件不帶 package）＋ `NEW_TASK |
RESET_TASK_IF_NEEDED`，系統會把它跟桌面開的視為同一筆、取代掉殘留的那張。android_intent_plus 因此
不再使用、已移除。

**重開懸浮球時 Dart 收不到 resumed** — 外掛每次顯示只送 `appIsResumed`，而 Flutter 的
`LifecycleChannel` 會吞掉跟上一次相同的狀態，所以懸浮層的 Dart 只有第一次顯示時收得到 resumed。
`main.dart` 靠它在重開時把形態重設成球，這段一直沒生效過。實測：解答小卡開著時從主 App 關閉懸浮球、
再打開，小卡被擠在球大小的視窗裡（出現 OVERFLOWED）。現在每次顯示先送 inactive 再送 resumed。
沒改成「關閉時送 paused」：關閉後馬上再顯示時，前一次的 onDestroy 可能晚於這次顯示才跑
（`main.dart` 的 `_show` 註解記過這個時序），會讓顯示中的懸浮層停在 paused。

**拖曳放手被當成點擊** — 視窗跟著手指移動，所以在視窗自己的座標裡，觸控點幾乎沒動，Flutter 的
點擊容許範圍（在 Android 上就是系統的 touch slop）只有在「視窗剛好落後手指一步」的那個事件才會被
超過。實測從左邊緣慢慢往內拖：
Flutter 最多只看到 13 個邏輯像素的位移，放手時觸發 `onTap`、面板就展開了；改動前的版本只差在那次
拖曳中剛好有一個事件落後（26 px）——是競態，不是規則。現在只要拖曳過，放手時就改送 cancel 給
Flutter，不送 up；單純點一下不受影響。為此「開始拖曳」的門檻也從上游的 5 個實體像素（約 2dp）
改成系統的 touch slop：否則手指點的時候晃超過 2dp 就算拖曳，球會變得點不開。Flutter 判定點擊用的
也是這個值，所以兩邊共用同一條分界——低於它兩邊都算點擊，超過它兩邊都算拖曳（這台 Sony 實測：晃
40px 仍會開面板，50px 就算拖曳）。

**新增：拖去 X 關閉、放手吸邊改由原生做**（不是缺陷，見「拖去 X 關閉」）。三個實作上的取捨：

- X 是另一個獨立的原生視窗，不是畫在 Flutter 裡：外掛只有一個 Flutter 視窗，要畫在裡面，就得在
  拖曳途中把球的視窗撐成全螢幕——那正是約 280ms 的位置延遲，手指底下的座標原點還會跳一次
- X 的視窗必須比球的**先**加入（同類型視窗依加入順序疊放）。第一版是開始拖曳才加，錄影看得到
  球滑進去那幾幀被 X 蓋住；現在改成懸浮窗一出現就加入、平常透明
- 吸邊原本是 Dart 每 20ms 透過 channel 搬一次視窗，沒對齊螢幕刷新，錄影逐幀量到約一半的幀
  完全沒動（每幀位移 76、0、0、52、31、0、0、0、24…）。改成原生由 Choreographer 驅動的彈簧；
  放手吸邊這件事，Dart 只剩開關（`setSnapToEdge`），以及「現在是不是球」（`setBallMode`，
  解答小卡也能拖，但不吸邊、也不出 X）。收合時的落點仍由 Dart 直接擺到邊上，但那是一次到位，
  不是動畫

### `flutter_accessibility_service`（1.2.0 的複本）

十一處，全部由實機量測發現：

| 缺陷 | 後果 |
|---|---|
| `nextTexts` 被宣告、被送出，**從未被填值** | `nodesText` 是死欄位、永遠空陣列 |
| 子節點 `capturedText` 塞 CharSequence | null 被字串化成字面的 `"null"` |
| Dart `map['capturedText'].toString()` 無條件呼叫 | 同上 |
| 完全沒有 `contentDescription` | 圖示按鈕沒有 text，整類元件讀不到 |
| 樹深度上限寫死 15、Dart 不可調 | logcat 實測到截斷，帶文字的葉節點被丟掉 |
| `getSource()` 為 null 的事件整筆丟棄 | **點擊事件幾乎必然 `source=null`**，整類事件靜默消失 |
| 廣播只是訊號、payload 放在 SharedPreferences 單一欄位 | 事件密集時後蓋前，天生掉事件 |
| `performGlobalAction` 只檢查設定旗標、無條件回 `true` | 失敗看起來像成功 |
| 沒人監聽時照樣處理每一筆事件 | 服務只要開著，系統就一直綁著它、行程常駐；連狀態列時鐘更新，都會在主執行緒走一次節點樹、寫一次 SharedPreferences、發一次廣播 |
| `onStartCommand` 回 `START_STICKY` 又無條件讀 intent | 外掛用 `startService` 傳指令後，服務停在 started 狀態；行程一被殺（滑掉最近任務、記憶體回收），系統就以 null intent 重啟 → NPE，幾秒後再一次 → 「屢次停止運作」 |
| `onServiceConnected` 對未快取的 engine 做 `requireNonNull` | 行程被服務拉起時必定 NPE → crash loop → 服務永遠連不上 |

最後一項最難查：系統設定頁顯示「已啟用」，但服務從未真正連上，而 `dispatchGesture` 對此
的處理是**靜默回 false、不留任何 log**。是在原生埋一行 log 才看出 `source=null` 與 crash
loop 的。

`onStartCommand` 那項是實際遇到的「無障礙突然失效」：`adb logcat -b crash` 留著相隔幾秒的兩次
NPE。重現方式：`adb shell run-as com.louis.overlay_demo am startservice --user 0 -n <服務元件>`
讓服務進入 started 狀態（不帶 `--user 0` 會被擋），再用 `run-as … kill -9` 殺掉行程。

另外**新增**一項上游沒有的功能（不是缺陷）：`takeScreenshot` 直接回傳 RGBA 像素。上游只有
`GLOBAL_ACTION_TAKE_SCREENSHOT`，檔案丟進相簿、還會跳系統截圖 UI，App 讀不回自己剛拍的
畫面。失敗不吞，轉成 `NO_ACCESS` / `TOO_FREQUENT` / `SECURE_WINDOW` / `NOT_CONNECTED` /
`UNSUPPORTED`，呼叫端才給得出可行動的提示。服務 XML 要宣告 `canTakeScreenshot`。

## 已知問題

**視窗改變大小 / 位置時，畫面會落後參數約 280ms。** 實測 `getOverlayPosition()` 回報的
LayoutParams 在 1ms 內就是最終值，但畫面上的視窗要約 283ms 才追到位——搬移發生在
surface / 合成器那層，Dart 這側碰不到。

目前用三個手段壓住，**都是遮蔽症狀、非修正成因**：

1. 轉場期間什麼都不畫（`_BallMode.switching`）
2. 動視窗前先 `await endOfFrame`，確保被系統拉伸的是空白而不是那顆球
3. 幾何到位後再延遲才顯示（`kCollapseRevealDelay` 300ms / `kExpandRevealDelay` 200ms），
   值是逐幀量出來的

左右兩側手感原本不同，也是同一個成因：展開一律把視窗錨到 (0,0)，球在左緣時 x 不用搬，
在右緣時要橫移將近一個螢幕寬。第 3 點把兩邊拉齊。

**搬視窗的動畫在 120Hz 下仍偶有不均**：吸入 X、吸邊、拖曳，都是用 `updateViewLayout` 一幀搬一次
小視窗。錄影量到的每幀位移仍會忽大忽小（例如 84、34、52、0），推測是跨行程套用位置的時機不總是
落在同一幀，也可能只是錄影取樣的鋸齒，**沒有分辨出是哪一個**。系統的泡泡能完全平滑，是因為它在
大視窗裡移動 View，再用隱藏 API 限縮可觸控的區域，一般 App 用不了。

**錄製的樹去重會漏收**：指紋只取 `packageName + 子節點數 + 前 8 段文字`，兩個外觀不同但
這幾項剛好相同的畫面會被當成「樹沒變」而跳過整棵樹，只留事件本身。

**面板展開期間轉向，版面不會即時更新**：螢幕尺寸是在每個動作開頭現問的（轉向時懸浮層的
Dart 收不到通知），要到下一個動作才用上新的尺寸。

**手勢導覽下，從螢幕邊緣起拖可能被系統的返回手勢搶走**：球貼邊時，觸控若落在最外側那一小段，
系統會當成返回手勢，懸浮窗只收到取消、球拖不動（實測離邊 24dp 起拖時好時壞、42dp 正常）。
從球的內側起拖即可。拖到一半才被系統接走的話，取消時會照常吸回邊緣。

## 踩過的坑（都寫在 `lib/main.dart` 的註解裡）

- `showOverlay` 的 width/height 是 px，`resizeOverlay` 與 `startPosition` 是 dp
- `resizeOverlay` 的高度沒有 MATCH_PARENT sentinel（外掛判斷式恆真），只能餵實際 dp
- 視窗對齊用 `topLeft`；置中對齊會以「扣掉系統列的 parent frame」為基準，與 `display.size` 差一個 inset
- `closeOverlay` 不會重建 isolate（引擎是快取的），`initState` 不會重跑
- `closeOverlay` 也**不會給懸浮層的 Dart 側任何訊號**——它只拆原生 View。所以那邊的
  timer 與訂閱都必須自己確認 `isActive()`，否則視窗關了它還在跑，而且使用者已經按不到停止鍵
- 原生 `onStartCommand` 最後還會 `moveOverlay` 一次，會蓋掉 Dart 這側擺的位置
- `positionGravity != none` 時，**連單純點一下**也會排一個吸附動畫 timer，跟程式化移動搶 LayoutParams
- `dispatchGesture` 的座標是實體像素，不是 dp
- 連點目標若落在球底下，那一下會被我們自己的懸浮窗吃掉（所以吸附要能關）
- 選點用 `onTapUp` 而非 `onTapDown`：後者會在手指還按著時換掉 widget tree，
  後續事件落到剛建出來的收合手勢上，面板就被關掉了
- 系統會在部分設定頁**主動隱藏第三方懸浮窗**（防 tapjacking），繞不過；但無障礙服務不受
  影響，所以那段期間錄製照常進行
- 懸浮層的 `display.size` 不會跟著轉向更新（引擎沒有 Activity），要向原生問
- 視窗尺寸是 dp 換成整數 px，捨入後可能比算的小零點幾個像素：內容寫死尺寸就會 overflow，
  要讓它填滿剩下的空間；外框（`Border`）也會吃掉內容區，算尺寸時要算進去
