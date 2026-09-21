# flutter-overlay-demo

**繁體中文** · [English](README.en.md)

Android 懸浮球（類 AssistiveTouch）的 Flutter 實作驗證。個人自用，非產品。

球可拖曳、吸附邊緣（可開關），點一下展開選單。選單提供：設定連點目標、開始／停止連點
（300ms 間隔）、螢幕截圖、**錄製操作流程**、清除錄製檔、返回 App。懸浮層做過的動作會回報
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

## 使用須知

這個工具會請求兩道高權限（懸浮窗、無障礙服務），能模擬觸控、截取畫面，**並能記錄其他
App 的畫面文字**。這些能力本身是 Android 官方 API、用途中性，但**怎麼用是使用者的責任**：
用在自己的裝置與帳號上沒有問題；用來干擾他人系統、繞過保護措施，或違反某個服務的使用
條款，後果自負。

隱私上做了幾件事：擷取路徑全數跳過 `isPassword()` 的節點；錄製檔放 app-private 內部儲存
而非外部儲存；`allowBackup` 關閉——Auto Backup 的預設範圍**正是**內部儲存，不關等於前門
關了後門開著；事件 payload 走 in-process 佇列而非系統廣播，不讓其他 App 有機會被動接收。

作者不對任何使用後果負責（見 `LICENSE`）。

## 授權

本專案採 MIT（見 `LICENSE`）。

`packages/` 下的兩個套件是第三方程式的**修改版**，原作者 Iheb Briki，原授權 MIT，
各自的 `LICENSE` 檔已完整保留。修改處在原始碼中以 `LOCAL PATCH` 註解標出，內容與理由
見下一節。這些修正都是上游的真實缺陷。

`flutter_accessibility_service` 的部分已回報：

- [#46](https://github.com/X-SLAYER/flutter_accessibility_service/issues/46) — `onServiceConnected` 的 crash loop
- [#47](https://github.com/X-SLAYER/flutter_accessibility_service/issues/47) — 五個擷取缺陷，附帶兩個未主張解法的架構問題

`flutter_overlay_window` 的兩個沒報：上游最後發布是 2025-04，已停滯約 17 個月。

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
