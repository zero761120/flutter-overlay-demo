# flutter-overlay-demo

Android 懸浮球（類 AssistiveTouch）的 Flutter 實作驗證。個人自用，非產品。

球可拖曳、吸附邊緣，點一下展開選單；選單提供模擬點擊（可連點）與螢幕截圖。
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

`packages/flutter_accessibility_service/` 是 pub.dev 1.2.0 的複本（MIT，作者 Iheb Briki），
透過 `dependency_overrides` 取代上游。**只改了一處**：

`AccessibilityListener.onServiceConnected()` 原本對一個「只在 `onAttachedToActivity`
才會被建立」的快取 engine 做 `Objects.requireNonNull`。當行程是被無障礙服務拉起來的
（重裝後、開機後），Activity 還沒跑過、快取是空的 → NPE → 行程崩潰 → 系統重綁 → 再崩，
形成 crash loop。服務因此從未真正連上，而 `dispatchGesture` 對「服務沒連上」的處理是
**靜默回 false、不留任何 log**，從外面完全看不出原因。

修正是讓它在沒有 engine 時略過那個 overlay 功能（我們沒用到）。

## 已知問題

**收合時球的位置會有約 280ms 的追趕。** 實測 `getOverlayPosition()` 回報的 LayoutParams
在 1ms 內就是最終值，但畫面上的視窗要約 283ms 才追到位——搬移發生在 surface / 合成器那層，
Dart 這側碰不到。目前的處置是收合後延遲 180ms 才把球畫出來（`kCollapseRevealDelay`），
**遮蔽症狀、非修正成因**。

## 踩過的坑（都寫在 `lib/main.dart` 的註解裡）

- `showOverlay` 的 width/height 是 px，`resizeOverlay` 與 `startPosition` 是 dp
- `resizeOverlay` 的高度沒有 MATCH_PARENT sentinel（外掛判斷式恆真），只能餵實際 dp
- 視窗對齊用 `topLeft`；置中對齊會以「扣掉系統列的 parent frame」為基準，與 `display.size` 差一個 inset
- `closeOverlay` 不會重建 isolate（引擎是快取的），`initState` 不會重跑
- 原生 `onStartCommand` 最後還會 `moveOverlay` 一次，會蓋掉 Dart 這側擺的位置
- `positionGravity != none` 時，**連單純點一下**也會排一個吸附動畫 timer，跟程式化移動搶 LayoutParams
- `dispatchGesture` 的座標是實體像素，不是 dp
