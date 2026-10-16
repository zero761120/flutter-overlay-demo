# flutter-overlay-demo

**繁體中文** · [English](README.en.md)

Android 懸浮球（類 AssistiveTouch）的 Flutter 實作驗證。個人自用，非產品。

球可拖曳、吸附邊緣（可開關），點一下展開選單。選單提供：設定連點目標、開始／停止連點
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
`adb shell input` + `adb exec-out screencap` 就不會碰到。

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
見下一節。修正的部分都是上游的真實缺陷或沒處理到的限制；另有一項新增功能（截圖回傳像素），
也標在下一節。

`flutter_accessibility_service` 的部分已回報：

- [#46](https://github.com/X-SLAYER/flutter_accessibility_service/issues/46) — `onServiceConnected` 的 crash loop
- [#47](https://github.com/X-SLAYER/flutter_accessibility_service/issues/47) — 五個擷取缺陷，附帶兩個未主張解法的架構問題

`flutter_overlay_window` 的都沒報：上游最後發布是 2025-04，已停滯約 17 個月。

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
`display.size` 同語意），Dart 在每個要用到尺寸的動作開頭現問一次。

### `flutter_accessibility_service`（1.2.0 的複本）

九處，全部由實機量測發現：

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
| `onServiceConnected` 對未快取的 engine 做 `requireNonNull` | 行程被服務拉起時必定 NPE → crash loop → 服務永遠連不上 |

最後一項最難查：系統設定頁顯示「已啟用」，但服務從未真正連上，而 `dispatchGesture` 對此
的處理是**靜默回 false、不留任何 log**。是在原生埋一行 log 才看出 `source=null` 與 crash
loop 的。

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

**錄製的樹去重會漏收**：指紋只取 `packageName + 子節點數 + 前 8 段文字`，兩個外觀不同但
這幾項剛好相同的畫面會被當成「樹沒變」而跳過整棵樹，只留事件本身。

**面板展開期間轉向，版面不會即時更新**：螢幕尺寸是在每個動作開頭現問的（轉向時懸浮層的
Dart 收不到通知），要到下一個動作才用上新的尺寸。

**手勢導覽下，從螢幕邊緣起拖可能被系統的返回手勢搶走**：球貼邊時，觸控若落在最外側那一小段，
系統會當成返回手勢，懸浮窗只收到取消，拖不動也不會吸邊（實測離邊 24dp 起拖時好時壞、
42dp 正常）。從球的內側起拖即可。

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
