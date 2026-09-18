import 'dart:async';
import 'dart:ui' as ui;

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_accessibility_service/constants.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:flutter_accessibility_service/gesture_description.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:overlay_demo/l10n/app_localizations.dart';

/// 懸浮球收合後的邊長（dp）。
///
/// 48dp 是 Android 建議的最小可點擊尺寸。視窗本身就只有球那麼大、沒有額外的觸控邊界，
/// 再往下縮會直接變成按不準。
const int kBallDp = 48;

/// 展開後的面板尺寸（dp）。
const int kPanelWidthDp = 240;
const int kPanelHeightDp = 360;

/// 連點間隔。
const Duration kClickInterval = Duration(milliseconds: 300);

/// 收合後延遲多久才把球畫出來。
///
/// **這是遮蔽症狀、不是修正成因。** 實測收合時 `getOverlayPosition()` 回報的
/// LayoutParams 在 1ms 內就是最終值，但畫面上的視窗要約 283ms 才追到位——搬移發生在
/// surface / 合成器那層，Dart 這側碰不到。與其讓球「飄過去」，不如等 surface 追得
/// 差不多了再顯示，變成乾脆的消失再出現。
///
/// 值是量出來的：180ms 時揭露，球還差 70px 沒追完（肉眼是「小小飄回定位」），
/// 而 surface 的收斂率約每幀 0.7，再給 ~7 幀就進到個位數像素。
const Duration kCollapseRevealDelay = Duration(milliseconds: 300);

/// 展開後延遲多久才把面板畫出來。同上，遮蔽 surface 的追趕。
///
/// 展開一律把視窗變成「全螢幕、錨在 (0,0)」。球在左緣時 x 本來就是 0、surface 只需
/// 長大；球在右緣時還得橫移將近一個螢幕寬，追趕距離差很多——這就是左右兩側手感不同的
/// 原因。用同一段延遲把兩邊拉齊。
const Duration kExpandRevealDelay = Duration(milliseconds: 200);

/// 一套慣用的藍色主題。
/// 主色日夜同色，底色與文字分日夜。這裡只搬懸浮球 demo 用得到的那幾個。
abstract final class BlueSkin {
  static const Color main = Color(0xFF2278FF);
  static const Color lightBg1 = Color(0xFFFFFFFF);
  static const Color lightBg2 = Color(0xFFF7F7F7);
  static const Color lightText1 = Color(0xFF000000);
  static const Color lightText3 = Color(0xFF6880A3);
  static const Color darkBg1 = Color(0xFF081F2D);
  static const Color darkText1 = Color(0xFFFFFFFF);
  static const Color darkText3 = Color(0xFF7DA1B4);
}

ThemeData buildTheme(Brightness brightness) {
  final bool dark = brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: BlueSkin.main,
      brightness: brightness,
      primary: BlueSkin.main,
      surface: dark ? BlueSkin.darkBg1 : BlueSkin.lightBg1,
      onSurface: dark ? BlueSkin.darkText1 : BlueSkin.lightText1,
      onSurfaceVariant: dark ? BlueSkin.darkText3 : BlueSkin.lightText3,
    ),
    scaffoldBackgroundColor: dark ? BlueSkin.darkBg1 : BlueSkin.lightBg2,
  );
}

/// 螢幕尺寸（dp）。兩個 isolate 都從同一個來源推導，否則主 App 給的初始座標會跟
/// 懸浮窗自己算的對不上。
Size screenSizeDp() {
  final ui.Display display =
      WidgetsBinding.instance.platformDispatcher.views.first.display;
  return display.size / display.devicePixelRatio;
}

/// 收合狀態下球的落點：貼右緣、垂直置中。
Offset idleBallPosition(Size screen) =>
    Offset(screen.width - kBallDp, (screen.height - kBallDp) / 2);

/// 主 App 進入點。
void main() => runApp(const DemoApp());

/// 懸浮窗進入點。
///
/// 名稱必須是 `overlayMain`：OverlayService.java 把它寫死成 DartEntrypoint，
/// 改名會啟動一個跑不起來的第二引擎、畫面全黑且無錯誤訊息。
@pragma('vm:entry-point')
void overlayMain() => runApp(const OverlayApp());

/// `flutter_accessibility_service` 的進入點。
///
/// 它在 `onAttachedToActivity` 會用這個名字建一個引擎丟進快取，而
/// `AccessibilityListener.onServiceConnected` 會 `Objects.requireNonNull` 去拿它。
/// 我們沒有用到它的 overlay 功能，但**不能不定義**——否則 isolate 起不來，
/// log 會出現 `Could not resolve main entrypoint function`。
@pragma('vm:entry-point')
void accessibilityOverlay() => runApp(const SizedBox.shrink());

// ─────────────────────────── 主 App ───────────────────────────

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (BuildContext context) =>
          AppLocalizations.of(context)!.appTitle,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  bool _granted = false;
  bool _active = false;
  bool _a11y = false;
  final List<String> _logs = <String>[];
  StreamSubscription<dynamic>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 懸浮窗那側主動回報的訊息（按鈕事件等）從這裡收。
    _sub = FlutterOverlayWindow.overlayListener.listen(_onOverlayMessage);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 權限是在系統設定頁授予的，回到前景才知道使用者剛剛按了什麼。
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final bool granted = await FlutterOverlayWindow.isPermissionGranted();
    final bool active = await FlutterOverlayWindow.isActive();
    final bool a11y =
        await FlutterAccessibilityService.isAccessibilityPermissionEnabled();
    if (!mounted) return;
    setState(() {
      _granted = granted;
      _active = active;
      _a11y = a11y;
    });
  }

  void _onOverlayMessage(dynamic message) {
    if (message == 'close') {
      _close();
      return;
    }
    if (!mounted) return;
    // 懸浮層送來的字串已自帶時間，這裡不再加一次。
    setState(() => _logs.insert(0, '$message'));
  }

  Future<void> _request() async {
    await FlutterOverlayWindow.requestPermission();
    await _refresh();
  }

  Future<void> _show() async {
    // 常駐通知的文案在 await 之前取，避免跨 async gap 用 context。
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final String title = l10n.appTitle;
    final String content = l10n.pickHint;
    if (!_granted) {
      await _request();
      if (!_granted) return;
    }
    // showOverlay 的 width / height 直接塞進 WindowManager.LayoutParams，單位是 px；
    // 但 resizeOverlay 與 startPosition 內部都會再跑一次 dpToPx，單位是 dp。
    // 這個不一致是外掛的已知行為，首次開啟得自己乘 devicePixelRatio。
    final Size screen = screenSizeDp();
    final Offset ball = idleBallPosition(screen);
    final int ballPx =
        (kBallDp *
                WidgetsBinding
                    .instance
                    .platformDispatcher
                    .views
                    .first
                    .display
                    .devicePixelRatio)
            .round();
    await _startOverlay(ballPx, ball, title, content);
    // closeOverlay 走的是 stopService，真正移除視窗的是稍後才跑的 onDestroy。
    // 「關閉→馬上顯示」時那個 onDestroy 會晚到、把剛建好的視窗一起收走（畫面上就是
    // 「開關幾次之後球就不見了」），所以開完要確認一次，沒撐住就重開。
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!await FlutterOverlayWindow.isActive()) {
      await _startOverlay(ballPx, ball, title, content);
    }
    await _refresh();
  }

  Future<void> _startOverlay(
    int ballPx,
    Offset ball,
    String overlayTitle,
    String overlayContent,
  ) {
    return FlutterOverlayWindow.showOverlay(
      width: ballPx,
      height: ballPx,
      alignment: OverlayAlignment.topLeft,
      // 原生在 onStartCommand 的最後還會 moveOverlay 一次，會蓋掉懸浮窗這側開場自己
      // 擺的位置；直接把預期落點交給它，兩邊算出同一組座標就不會打架。
      startPosition: OverlayPosition(ball.dx, ball.dy),
      flag: OverlayFlag.defaultFlag,
      // 拖曳交給原生（Flutter 接管的話每次換視窗大小都會有轉場跳動），但**關掉原生的
      // 吸附動畫**：ACTION_UP 只要 positionGravity != none 就會排一個每 25ms 一拍的
      // timer 去吸附邊緣，連「只點一下、沒拖曳」也會排。那個 timer 跟展開／收合時的
      // updateOverlayPosition 搶同一組 LayoutParams，視窗會被它一路拉回點擊前的位置。
      // 它的每一拍是 post 到主執行緒佇列執行的，點擊當下主執行緒正忙，「到位就取消」
      // 的判斷會排在我們搬完視窗之後才跑 → 落差變成整個螢幕 → 開始動畫。
      // 因此靠「等它收斂」是擋不住的（讀到的穩定是假的，動畫根本還沒開始），
      // 只能不讓它被排程。吸附改由收合時自己做，時機完全可控。
      positionGravity: PositionGravity.none,
      enableDrag: true,
      overlayTitle: overlayTitle,
      overlayContent: overlayContent,
      visibility: NotificationVisibility.visibilityPublic,
    );
  }

  Future<void> _close() async {
    await FlutterOverlayWindow.closeOverlay();
    // closeOverlay 走的是 stopService，而 isRunning 要到 onDestroy 才翻成 false。
    // 只查一次會查到還沒收乾淨的 true，按鈕就永遠停在 disabled（之後沒有任何事件
    // 會再觸發更新）。這裡等它真的收完，逾時就照最後一次結果走。
    for (int i = 0; i < 10; i++) {
      if (!await FlutterOverlayWindow.isActive()) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await _refresh();
  }

  Future<void> _ping() async {
    await FlutterOverlayWindow.shareData(
      AppLocalizations.of(context)!.helloFromApp(_now()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _StatusCard(
            granted: _granted,
            active: _active,
            a11y: _a11y,
            l10n: l10n,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _granted ? null : _request,
            icon: const Icon(Icons.shield_outlined),
            label: Text(l10n.permOverlayGrant),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            // 這道權限沒有 runtime dialog，只能把使用者送到系統設定頁自己開。
            onPressed: _a11y
                ? null
                : () async {
                    await FlutterAccessibilityService.requestAccessibilityPermission();
                    await _refresh();
                  },
            icon: const Icon(Icons.accessibility_new),
            label: Text(l10n.permA11yGrant),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _active ? null : _show,
            icon: const Icon(Icons.bubble_chart_outlined),
            label: Text(l10n.ballShow),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _active ? _close : null,
            icon: const Icon(Icons.close),
            label: Text(l10n.ballClose),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _active ? _ping : null,
            icon: const Icon(Icons.send_outlined),
            label: Text(l10n.sendToBall),
          ),
          const SizedBox(height: 24),
          Row(
            children: <Widget>[
              Text(
                l10n.actionLog,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              TextButton(
                onPressed: _logs.isEmpty ? null : () => setState(_logs.clear),
                child: Text(l10n.clear),
              ),
            ],
          ),
          if (_logs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                l10n.actionLogEmpty,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ..._logs.map(
              (String line) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(line, style: const TextStyle(fontSize: 13)),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.granted,
    required this.active,
    required this.a11y,
    required this.l10n,
  });

  final bool granted;
  final bool active;
  final bool a11y;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: <Widget>[
            _StatusRow(label: l10n.permOverlay, ok: granted),
            _StatusRow(label: l10n.ballRunning, ok: active),
            _StatusRow(label: l10n.permA11y, ok: a11y),
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.ok});

  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 8,
      children: <Widget>[
        Icon(
          ok ? Icons.check_circle : Icons.cancel,
          size: 20,
          color: ok ? Colors.green : Colors.redAccent,
        ),
        Text(label),
      ],
    );
  }
}

// ─────────────────────────── 懸浮窗 ───────────────────────────

class OverlayApp extends StatelessWidget {
  const OverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 懸浮層是獨立 isolate，拿不到主 App 的 theme / locale，得自己各配一份。
    // 兩邊都跟隨系統，所以看起來會一致。
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      // 背景必須透明，否則整個懸浮窗會是一塊不透明矩形。
      color: Colors.transparent,
      home: const Material(color: Colors.transparent, child: FloatingBall()),
    );
  }
}

class FloatingBall extends StatefulWidget {
  const FloatingBall({super.key});

  @override
  State<FloatingBall> createState() => _FloatingBallState();
}

/// 懸浮窗目前的形態，決定視窗要多大、Flutter 要畫什麼。
enum _BallMode { idle, switching, expanded }

class _FloatingBallState extends State<FloatingBall>
    with WidgetsBindingObserver {
  /// 懸浮窗形態的縮放 / 移動走這條（由 OverlayService 註冊在第二引擎上）。
  static const MethodChannel _selfChannel = MethodChannel('x-slayer/overlay');

  _BallMode _mode = _BallMode.idle;

  /// 展開當下球的位置（dp，螢幕左上角為原點）。
  ///
  /// 拖曳全程交給原生，Flutter 不追蹤座標——要用的時候直接問
  /// `getOverlayPosition()`。實測懸浮窗這側呼叫得到主引擎 channel 上的 method
  /// （第二引擎是 `FlutterEngineGroup.createAndRunEngine` 建的，會自動註冊 plugin），
  /// 所以不需要自己接管拖曳來換取「知道球在哪」。
  Offset _ballAtExpand = Offset.zero;

  /// 自己做的吸附動畫。原生那個關掉了（理由見 showOverlay 的 positionGravity 註解），
  /// 這一份的關鍵差別是**我們握有取消權**：展開前一定能停掉，不會跟搬視窗搶。
  Timer? _snapTimer;

  /// 放手後要不要自動吸附到邊緣。
  ///
  /// 連點情境通常要關掉：`dispatchGesture` 是派到系統層，目標若落在球底下，那一下會被
  /// 我們自己的懸浮窗吃掉；吸附把球釘在邊緣，剛好讓「目標在邊緣附近」變成高機率情境。
  /// 純截圖情境則留著比較順手。
  bool _snapEnabled = true;

  /// 連點的目標座標（dp，螢幕左上角為原點）。null 代表還沒設定。
  Offset? _target;

  /// 正在等使用者點一下畫面來指定目標。
  bool _picking = false;

  Timer? _clickTimer;
  bool get _clicking => _clickTimer?.isActive ?? false;

  /// 無障礙服務有沒有被使用者啟用。展開面板時查一次。
  bool _a11yEnabled = false;

  /// 連點失敗的可行動提示，成功時清空。
  String? _clickError;

  String? _lastFromApp;
  StreamSubscription<dynamic>? _sub;

  Size get _screen => screenSizeDp();

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  /// 球貼在右半邊還是左半邊——展開方向要跟著它走。
  bool get _onRight => _ballAtExpand.dx + kBallDp / 2 > _screen.width / 2;

  @override
  void initState() {
    super.initState();
    _sub = FlutterOverlayWindow.overlayListener.listen((dynamic message) {
      if (!mounted) return;
      setState(() => _lastFromApp = '$message');
    });
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _snapTimer?.cancel();
    _clickTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 關閉懸浮球只是把 View 從 WindowManager 拆下來，引擎與 isolate 都留在快取裡，
    // 所以再開一次時 initState 不會重跑，_mode 會沿用上一輪的值（關閉時若正展開著，
    // 下次開啟就會用全螢幕的排版去畫一個球大小的視窗）。OverlayService 每次
    // onStartCommand 都會送一個 appIsResumed，拿它當重新掛載的訊號重置。
    // 位置與尺寸都由原生依 showOverlay 的參數擺好，這裡不必也不該再去動。
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() => _mode = _BallMode.idle);
    }
  }

  // ── 模擬點擊與截圖（走無障礙服務）──

  Future<void> _refreshA11y() async {
    final bool enabled =
        await FlutterAccessibilityService.isAccessibilityPermissionEnabled();
    if (!mounted) return;
    setState(() => _a11yEnabled = enabled);
  }

  Future<void> _startClicking() async {
    final Offset? target = _target;
    if (target == null) return;
    // dispatchGesture 的座標是**實體像素**，Flutter 這側拿到的是 dp，要自己換算。
    final double dpr = WidgetsBinding
        .instance
        .platformDispatcher
        .views
        .first
        .display
        .devicePixelRatio;
    final GesturePoint point = GesturePoint(target.dx * dpr, target.dy * dpr);
    final GestureDescription tap = GestureDescription(
      strokes: <GestureStroke>[
        GestureStroke(path: <GesturePoint>[point], duration: 50),
      ],
    );
    _clickTimer?.cancel();
    _clickError = null;
    _clickTimer = Timer.periodic(kClickInterval, (Timer t) async {
      // 主 App 按「關閉懸浮球」走的是 stopService，只拆掉原生的 View；懸浮層的 isolate
      // 與引擎都留在快取裡，這個 timer 不會收到任何訊號。不自己檢查的話，視窗沒了、
      // 「停止連點」也按不到，它卻還在每 300ms 戳螢幕。
      if (!await FlutterOverlayWindow.isActive()) {
        t.cancel();
        return;
      }
      // 面板展開時整個螢幕都是我們的視窗，這時候派手勢只會戳到自己，先跳過。
      if (_mode != _BallMode.idle) return;
      final bool ok = await FlutterAccessibilityService.dispatchGesture(tap);
      if (!ok) {
        // 外掛在「服務沒真正連上」時是**靜默**回 false 的（原生那條 instance == null
        // 分支沒有任何 log）。最常見的成因是 app 重裝後服務先被重新綁定、那時
        // onAttachedToActivity 還沒跑過，它要的引擎快取是空的 → onServiceConnected
        // 丟 NPE。設定頁看起來仍是「已啟用」，但其實沒連上。
        t.cancel();
        if (mounted) {
          setState(() => _clickError = _l10n.dispatchFailed);
        }
      }
    });
    setState(() {});
    _report(_l10n.logStartClicking(kClickInterval.inMilliseconds));
    // 收合面板，讓點擊真的落到下面那個 App。
    await _collapse();
  }

  void _stopClicking() {
    _clickTimer?.cancel();
    _report(_l10n.stopClicking);
    setState(() {});
  }

  /// 把主 App 叫回前景。
  ///
  /// 懸浮層與主 App 是兩個 isolate，這裡沒有 BuildContext 可以導頁，只能走 Android
  /// intent 把 Activity 拉起來。先收合，否則全螢幕的懸浮層會蓋在它上面。
  Future<void> _openMainApp() async {
    await _collapse();
    _report(_l10n.backToApp);
    const AndroidIntent intent = AndroidIntent(
      action: 'action_main',
      package: 'com.louis.overlay_demo',
      componentName: 'com.louis.overlay_demo.MainActivity',
      flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK, Flag.FLAG_ACTIVITY_SINGLE_TOP],
    );
    await intent.launch();
  }

  /// 把懸浮層做過的動作回報給主 App，讓那邊的「訊息紀錄」變成有用的歷程。
  void _report(String action) {
    FlutterOverlayWindow.shareData('${_now()}  $action');
  }

  Future<void> _takeScreenshot() async {
    final String label = _l10n.screenshot;
    final String failed = _l10n.dispatchFailed;
    // 系統截圖會把我們的懸浮層一起拍進去，先收合再拍。
    await _collapse();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final bool ok = await FlutterAccessibilityService.performGlobalAction(
      GlobalAction.globalActionTakeScreenshot,
    );
    // 確定成功才記錄。無條件記一筆的話，「服務其實沒連上」會留下一筆看起來成功的紀錄，
    // 那比沒有紀錄更糟。
    if (!ok) {
      if (mounted) setState(() => _clickError = failed);
      return;
    }
    _report(label);
  }

  // ── 展開 / 收合 ──

  /// 視窗是從自己被錨定的那一角長出來的，球貼在左緣時面板會整片長到畫面外。
  /// 展開時改成讓視窗鋪滿螢幕、由 Flutter 依 `_onRight` 決定面板靠哪邊，
  /// 順便得到「點空白處收合」的行為。
  // ── 吸附 ──
  //
  // 原生拖曳期間 OnTouchListener 一律 return false，事件照樣會傳到 Flutter，
  // 所以放手這件事這裡收得到 —— 不必為了知道「拖曳結束了」而把拖曳整個接管過來。

  void _onPointerUp(PointerUpEvent event) {
    if (!_snapEnabled || _mode != _BallMode.idle) return;
    _startSnap();
  }

  Future<void> _startSnap() async {
    _snapTimer?.cancel();
    final Size screen = _screen;
    final OverlayPosition pos = await FlutterOverlayWindow.getOverlayPosition();
    if (!mounted || _mode != _BallMode.idle) return;
    final double destX = pos.x + kBallDp / 2 > screen.width / 2
        ? screen.width - kBallDp
        : 0;
    double x = pos.x;
    // 沿用原生那條收斂曲線（每拍往目標收掉 1/3），手感一致。
    _snapTimer = Timer.periodic(const Duration(milliseconds: 20), (Timer t) {
      if (!mounted || _mode != _BallMode.idle) {
        t.cancel();
        return;
      }
      x = (2 * (x - destX)) / 3 + destX;
      if ((x - destX).abs() < 1) {
        x = destX;
        t.cancel();
      }
      _moveWindow(x.round(), pos.y.round());
    });
  }

  Future<void> _expand() async {
    // 吸附還在跑的話先停掉，否則它跟下面搬視窗的呼叫會搶同一組 LayoutParams。
    _snapTimer?.cancel();
    final OverlayPosition pos = await FlutterOverlayWindow.getOverlayPosition();
    _ballAtExpand = Offset(pos.x, pos.y);
    // 搬視窗與改尺寸是兩個原生呼叫，落在不同幀時中間會出現「已經搬走但還沒放大」這類
    // 半成品狀態，畫出來就像在滑動。切換期間索性什麼都不畫（見 build 的 switching），
    // 幾何到位了才換版型——視覺上是乾脆的切換，代價是約 1～3 幀的空白。
    setState(() => _mode = _BallMode.switching);
    // 讓「什麼都不畫」這一幀真的被光柵化，再去動視窗。
    //
    // Android 在視窗改變大小時，會把既有的 surface 內容**拉伸到新的邊界**，直到新的
    // frame 送達。setState 只是排了一次重繪，若不等它畫完就改尺寸，被拉伸的仍是上一張
    // 有球的畫面——看起來就是球瞬間變超大鋪滿螢幕。
    await WidgetsBinding.instance.endOfFrame;
    // 展開期間關掉原生拖曳（resizeOverlay 的第三個參數），否則整片全螢幕視窗都能拖。
    // 寬度傳 -1 代表 MATCH_PARENT；高度沒有等效的 sentinel（外掛的判斷式恆真、
    // 一律會跑 dpToPx），只能餵實際的 dp 值。
    // 兩個呼叫走同一條 channel、順序有保證，一起發出讓它們盡量落在同一幀。
    await Future.wait(<Future<void>>[
      _moveWindow(0, 0),
      _callOverlay(
        () => FlutterOverlayWindow.resizeOverlay(
          -1,
          _screen.height.ceil(),
          false,
        ),
      ),
    ]);
    await Future<void>.delayed(kExpandRevealDelay);
    if (!mounted) return;
    setState(() => _mode = _BallMode.expanded);
    _refreshA11y();
  }

  Future<void> _collapse() async {
    // 原生的吸附動畫關掉了，改在這裡自己吸附：收合本來就要指定落點，順手貼到最近的邊。
    // 吸附關掉時就原地放回去，不要偷偷把球挪走。
    final int x = _snapEnabled
        ? (_onRight ? (_screen.width - kBallDp).round() : 0)
        : _ballAtExpand.dx.round();
    final int y = _ballAtExpand.dy.round();
    _ballAtExpand = Offset(x.toDouble(), y.toDouble());
    setState(() => _mode = _BallMode.switching);
    // 讓「什麼都不畫」這一幀真的被光柵化，再去動視窗。
    //
    // Android 在視窗改變大小時，會把既有的 surface 內容**拉伸到新的邊界**，直到新的
    // frame 送達。setState 只是排了一次重繪，若不等它畫完就改尺寸，被拉伸的仍是上一張
    // 有球的畫面——看起來就是球瞬間變超大鋪滿螢幕。
    await WidgetsBinding.instance.endOfFrame;
    await Future.wait(<Future<void>>[
      _callOverlay(
        () => FlutterOverlayWindow.resizeOverlay(kBallDp, kBallDp, true),
      ),
      _moveWindow(x, y),
    ]);
    await Future<void>.delayed(kCollapseRevealDelay);
    if (!mounted) return;
    setState(() => _mode = _BallMode.idle);
  }

  /// 重新掛載當下 channel 可能還沒人接，短暫重試而不是讓例外中斷整個流程。
  ///
  /// 原生 `onStartCommand` 是**先**送 appIsResumed、**之後**才
  /// `flutterChannel.setMethodCallHandler`，中間這段空窗期打過去會吃到
  /// MissingPluginException。
  Future<void> _callOverlay(Future<void> Function() call) async {
    for (int attempt = 0; attempt < 5; attempt++) {
      try {
        await call();
        return;
      } on MissingPluginException {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  Future<void> _moveWindow(int x, int y) async {
    await _callOverlay(
      () => _selfChannel.invokeMethod<void>(
        'updateOverlayPosition',
        <String, int>{'x': x, 'y': y},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (_mode) {
      case _BallMode.idle:
        // 視窗跟球一樣大，球填滿它即可；拖曳由原生的 OnTouchListener 處理。
        return Align(alignment: Alignment.center, child: _buildBall());
      case _BallMode.switching:
        // 視窗幾何正在改，這幾幀畫什麼都會在錯的位置，乾脆不畫。
        return const SizedBox.shrink();
      case _BallMode.expanded:
        return _buildExpanded();
    }
  }

  Widget _buildExpanded() {
    if (_picking) return _buildPicker();
    final Size screen = _screen;
    // 面板貼著球所在那一邊，並對齊球的高度。
    final double top = (_ballAtExpand.dy + kBallDp - kPanelHeightDp).clamp(
      12.0,
      screen.height - kPanelHeightDp - 12,
    );
    return GestureDetector(
      onTap: _collapse,
      // 背景全透明，但仍要接得到點擊才能「點空白處收合」，所以手勢要吃整個區域。
      behavior: HitTestBehavior.opaque,
      child: SizedBox.expand(
        child: Stack(
          children: <Widget>[
            if (_target != null) _buildTargetMarker(_target!),
            Positioned(
              left: _ballAtExpand.dx,
              top: _ballAtExpand.dy,
              child: _buildBall(),
            ),
            Positioned(
              top: top,
              left: _onRight ? null : 12,
              right: _onRight ? 12 : null,
              // 吃掉面板本身的點擊，否則會穿到外層的收合手勢。
              child: GestureDetector(onTap: () {}, child: _buildPanel()),
            ),
          ],
        ),
      ),
    );
  }

  /// 選點模式：整片視窗都在等使用者點一下，記下那個座標當連點目標。
  Widget _buildPicker() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 視窗此時是全螢幕且位於 (0,0)，所以 globalPosition 就是螢幕座標。
      // 用 onTapUp 而不是 onTapDown：onTapDown 會在手指還按著時就換掉 widget tree，
      // 後續的事件落到剛建出來的收合手勢上，面板就被關掉了。等整個 tap 在 picker 內
      // 完成再切換，選完會直接回到面板。
      onTapUp: (TapUpDetails d) {
        setState(() {
          _target = d.globalPosition;
          _picking = false;
        });
        _report(
          _l10n.logSetTarget(
            d.globalPosition.dx.toStringAsFixed(0),
            d.globalPosition.dy.toStringAsFixed(0),
          ),
        );
      },
      child: Stack(
        children: <Widget>[
          Container(color: Colors.black.withValues(alpha: 0.35)),
          if (_target != null) _buildTargetMarker(_target!),
          Align(
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _l10n.pickHint,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 目標位置的十字標記。連點中換成紅色，一眼看得出現在正打在哪。
  Widget _buildTargetMarker(Offset target) {
    const double size = 28;
    final Color color = _clicking ? Colors.redAccent : Colors.orangeAccent;
    return Positioned(
      left: target.dx - size / 2,
      top: target.dy - size / 2,
      child: IgnorePointer(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                ),
              ),
              Container(width: 2, height: size, color: color),
              Container(width: size, height: 2, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBall() {
    return Listener(
      onPointerUp: _onPointerUp,
      child: GestureDetector(
        onTap: _mode == _BallMode.expanded ? _collapse : _expand,
        child: Container(
          width: kBallDp.toDouble(),
          height: kBallDp.toDouble(),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: BlueSkin.main.withValues(alpha: 0.9),
          ),
          child: const Icon(Icons.blur_on, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  Widget _buildPanel() {
    final Offset? target = _target;
    final String? error = _clickError;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: kPanelWidthDp.toDouble(),
      height: kPanelHeightDp.toDouble(),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Colors.black38,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                _l10n.menuTitle,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _collapse,
                child: const Icon(Icons.remove_circle_outline, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (!_a11yEnabled)
            _PanelNote(text: _l10n.a11yHint, color: Colors.redAccent)
          else if (error != null)
            _PanelNote(text: error, color: Colors.redAccent)
          else
            _PanelNote(
              text: target == null
                  ? _l10n.targetUnset
                  : _l10n.targetAt(
                      target.dx.toStringAsFixed(0),
                      target.dy.toStringAsFixed(0),
                    ),
              color: scheme.onSurfaceVariant,
            ),
          if (_lastFromApp != null)
            _PanelNote(
              text: _l10n.fromApp('$_lastFromApp'),
              color: scheme.onSurfaceVariant,
            ),
          const SizedBox(height: 6),
          // 內容長度會隨狀態文字變動，用可捲動區域包住，避免任何情況下 overflow。
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 6,
                children: <Widget>[
                  _PanelButton(
                    label: _l10n.snapEdge(_snapEnabled ? _l10n.on : _l10n.off),
                    onTap: () {
                      setState(() => _snapEnabled = !_snapEnabled);
                      _report(
                        _l10n.snapEdge(_snapEnabled ? _l10n.on : _l10n.off),
                      );
                    },
                  ),
                  _PanelButton(
                    label: _l10n.setTarget,
                    onTap: () => setState(() => _picking = true),
                  ),
                  _PanelButton(
                    label: _clicking ? _l10n.stopClicking : _l10n.startClicking,
                    filled: !_clicking,
                    danger: _clicking,
                    // 沒設定目標就沒得點；連點中則永遠可以停。
                    onTap: _clicking
                        ? _stopClicking
                        : (target == null ? null : _startClicking),
                  ),
                  _PanelButton(label: _l10n.screenshot, onTap: _takeScreenshot),
                  _PanelButton(label: _l10n.backToApp, onTap: _openMainApp),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelNote extends StatelessWidget {
  const _PanelNote({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: TextStyle(fontSize: 10, color: color));
  }
}

class _PanelButton extends StatelessWidget {
  const _PanelButton({
    required this.label,
    required this.onTap,
    this.filled = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    // 面板高度有限，統一用固定高度的扁按鈕，避免預設 padding 把版面撐爆。
    final ButtonStyle style = ButtonStyle(
      minimumSize: WidgetStateProperty.all(const Size.fromHeight(32)),
      padding: WidgetStateProperty.all(EdgeInsets.zero),
      textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 13)),
      foregroundColor: danger ? WidgetStateProperty.all(Colors.red) : null,
    );
    if (filled) {
      return FilledButton(onPressed: onTap, style: style, child: Text(label));
    }
    return OutlinedButton(onPressed: onTap, style: style, child: Text(label));
  }
}

String _now() {
  final DateTime t = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}
