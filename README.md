# flutter-overlay-demo

**繁體中文** · [English](README.en.md)

Android 懸浮球（類 AssistiveTouch）的 Flutter 實作驗證。個人自用，非產品。

球可拖曳、吸附邊緣（可開關），點一下展開選單。選單提供：設定連點目標、開始／停止連點
（300ms 間隔）、螢幕截圖、返回 App。懸浮層做過的動作會回報給主 App 列成紀錄。
主題與語系跟隨系統（日／夜、中／英），配色沿用一套慣用的藍色主題。

**僅 Android**——iOS 沒有任何公開 API 能畫到其他 App 之上。

## 需要兩道獨立權限

| 權限 | 用途 | 取得方式 |
|---|---|---|
| `SYSTEM_ALERT_WINDOW` | 懸浮窗本體 | 系統設定頁手動授權，**沒有 runtime dialog** |
| 無障礙服務 | 模擬點擊 / 截圖 | 設定 → 協助工具 手動啟用 |

## 建置

```bash
fvm flutter pub get
fvm flutter build apk --debug
```

## 本地修正的第三方套件

兩個套件各 vendor 一份修正版（`packages/`，走 `dependency_overrides`）。兩個問題同一種
性質：**上游假設自己只會被註冊在一個 engine 上**，而這個 app 有兩個（主 App 與懸浮層）。

### `flutter_overlay_window`（0.5.0 的複本）

`WindowSetup.messenger` 是靜態欄位，卻在 `onAttachedToEngine` 指派。外掛在兩個 engine
各註冊一次，後註冊的（懸浮層）覆蓋前者，於是 `OverlayService` 把懸浮層的 `shareData()`
**轉回懸浮層自己**，主 App 永遠收不到。改成在 `onAttachedToActivity` 指派——只有主
engine 會有 Activity，那是唯一能分辨兩者的地方。

### `flutter_accessibility_service`（1.2.0 的複本，MIT，作者 Iheb Briki）

**只改了一處**：

`AccessibilityListener.onServiceConnected()` 原本對一個「只在 `onAttachedToActivity`
才會被建立」的快取 engine 做 `Objects.requireNonNull`。當行程是被無障礙服務拉起來的
（重裝後、開機後），Activity 還沒跑過、快取是空的 → NPE → 行程崩潰 → 系統重綁 → 再崩，
形成 crash loop。服務因此從未真正連上，而 `dispatchGesture` 對「服務沒連上」的處理是
**靜默回 false、不留任何 log**，從外面完全看不出原因。

修正是讓它在沒有 engine 時略過那個 overlay 功能（我們沒用到）。

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

## 踩過的坑（都寫在 `lib/main.dart` 的註解裡）

- `showOverlay` 的 width/height 是 px，`resizeOverlay` 與 `startPosition` 是 dp
- `resizeOverlay` 的高度沒有 MATCH_PARENT sentinel（外掛判斷式恆真），只能餵實際 dp
- 視窗對齊用 `topLeft`；置中對齊會以「扣掉系統列的 parent frame」為基準，與 `display.size` 差一個 inset
- `closeOverlay` 不會重建 isolate（引擎是快取的），`initState` 不會重跑
- `closeOverlay` 也**不會給懸浮層的 Dart 側任何訊號**——它只拆原生 View。所以那邊的
  timer 必須自己確認 `isActive()`，否則視窗關了它還在跑，而且使用者已經按不到停止鍵
- `performGlobalAction` 只檢查「設定頁是否啟用」、不檢查「是否真的連上」，而且無條件
  回 `true`（已在 vendor 版補上連線檢查）
- 原生 `onStartCommand` 最後還會 `moveOverlay` 一次，會蓋掉 Dart 這側擺的位置
- `positionGravity != none` 時，**連單純點一下**也會排一個吸附動畫 timer，跟程式化移動搶 LayoutParams
- `dispatchGesture` 的座標是實體像素，不是 dp
- 連點目標若落在球底下，那一下會被我們自己的懸浮窗吃掉（所以吸附要能關）
- 選點用 `onTapUp` 而非 `onTapDown`：後者會在手指還按著時換掉 widget tree，
  後續事件落到剛建出來的收合手勢上，面板就被關掉了
