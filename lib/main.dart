import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_accessibility_service/accessibility_event.dart';
import 'package:flutter_accessibility_service/constants.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:flutter_accessibility_service/gesture_description.dart';
import 'package:flutter_accessibility_service/screen_capture.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:overlay_demo/l10n/app_localizations.dart';
import 'package:overlay_demo/meowdoku.dart';
import 'package:path_provider/path_provider.dart';

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

/// 保留幾份錄製檔。內容是其他 App 的畫面文字，不該無限累積。
const int kMaxRecordingFiles = 5;

/// 錄製期間多久才確認一次懸浮球還在。
const Duration kOverlayCheckInterval = Duration(seconds: 1);

/// 原始 JSON 在畫面上最多顯示多少字元。
const int kRawPreviewChars = 20000;

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

/// 懸浮層清空後等多久才截圖。
///
/// `endOfFrame` 只代表 framework 把空白那一幀送出去了，合成器換上它還要一兩幀；太早拍
/// 會把面板一起拍進去、壓在盤面上，辨識就會失敗。**未實測**，取約 6 幀的保守值。
const Duration kCaptureSettleDelay = Duration(milliseconds: 100);

/// 解答小圖裡盤面的邊長（dp），不隨盤面大小變。關卡多半是 8～10 格、最大 12 格：
/// 固定每格大小的話 8×8 會縮成一小塊，固定整張則格數少時每格自然變大。
/// 12×12 時每格 13dp，看得清楚又不會擋掉太多畫面。
const double kSolutionBoardDp = 156;
const double kSolutionPadDp = 8;

/// 小卡外框寬。尺寸要把它算進去：Border 會吃掉內容區，漏算就是上下各少 1dp 而 overflow。
const double kSolutionBorderDp = 1;
const double kSolutionHeaderDp = 20;

/// 解題失敗時那張小卡的尺寸（dp），只放一兩行錯誤訊息。
const Size kSolveErrorCardDp = Size(200, 110);

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
      // 只能不讓它被排程。吸附改成放手時由 OverlayService.springToEdge、收合時由
      // _collapse 自己做，時機完全可控。
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
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const RecordingsPage()),
            ),
            icon: const Icon(Icons.article_outlined),
            label: Text(l10n.recordings),
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

/// 錄製檔清單。
///
/// 錄製是懸浮層那個 isolate 寫的，但檔案落在 app 的 documents 目錄，主 App 讀得到同一份。
class RecordingsPage extends StatefulWidget {
  const RecordingsPage({super.key});

  @override
  State<RecordingsPage> createState() => _RecordingsPageState();
}

class _RecordingsPageState extends State<RecordingsPage> {
  List<File> _files = <File>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final List<File> files =
        dir
            .listSync()
            .whereType<File>()
            .where((File f) => f.path.contains('/flow-'))
            .toList()
          ..sort((File a, File b) => b.path.compareTo(a.path));
    if (!mounted) return;
    setState(() => _files = files);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.recordings)),
      body: _files.isEmpty
          ? Center(child: Text(l10n.recordingsEmpty))
          : ListView.separated(
              itemCount: _files.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int i) {
                final File f = _files[i];
                final int kb = (f.lengthSync() / 1024).round();
                return ListTile(
                  title: Text(f.uri.pathSegments.last),
                  subtitle: Text('$kb KB'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => RecordingDetailPage(file: f),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// 單份錄製的內容。
///
/// 預設只列點擊——原始 JSON 一份可能上百 KB、大半是 contentChanged 的雜訊，直接攤開沒人讀
/// 得下去。想追細節再展開原始內容。
class RecordingDetailPage extends StatefulWidget {
  const RecordingDetailPage({required this.file, super.key});

  final File file;

  @override
  State<RecordingDetailPage> createState() => _RecordingDetailPageState();
}

class _RecordingDetailPageState extends State<RecordingDetailPage> {
  List<dynamic> _steps = <dynamic>[];
  String _raw = '';
  bool _showRaw = false;
  bool _clicksOnly = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? _error;

  Future<void> _load() async {
    try {
      final String raw = await widget.file.readAsString();
      final List<dynamic> steps = jsonDecode(raw) as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _raw = raw;
        _steps = steps;
      });
    } catch (e) {
      // 檔案可能是半截的——錄製中途行程被砍掉就會留下寫到一半的 JSON。沒有這層的話
      // jsonDecode 直接拋例外、整頁變成紅色錯誤畫面，看不出是檔案壞了還是程式壞了。
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  bool _isTap(Map<String, dynamic> s) =>
      s['event'] == 'typeViewClicked' || s['event'] == 'typeViewLongClicked';

  /// 一步在畫面上怎麼稱呼：contentDescription 優先於 text，因為圖示按鈕只有前者。
  String _labelOf(Map<String, dynamic> s) {
    final Map<String, dynamic> node =
        (s['node'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final List<dynamic> texts = (s['texts'] as List<dynamic>?) ?? <dynamic>[];
    return node['desc']?.toString() ??
        node['text']?.toString() ??
        (texts.isNotEmpty ? texts.first.toString() : '');
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final List<Map<String, dynamic>> shown = _steps
        .cast<Map<String, dynamic>>()
        .where((Map<String, dynamic> s) => !_clicksOnly || _isTap(s))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.stepsCount(_steps.length)),
        actions: <Widget>[
          TextButton(
            onPressed: () => setState(() => _clicksOnly = !_clicksOnly),
            child: Text(_clicksOnly ? l10n.allSteps : l10n.clicksOnly),
          ),
        ],
      ),
      body: _error != null
          ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: <Widget>[
                ...shown.map((Map<String, dynamic> s) {
                  final Map<String, dynamic> node =
                      (s['node'] as Map<String, dynamic>?) ??
                      <String, dynamic>{};
                  final String label = _labelOf(s);
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      _isTap(s)
                          ? Icons.touch_app
                          : Icons.remove_red_eye_outlined,
                      size: 18,
                    ),
                    title: Text(label.isEmpty ? '(${s['event']})' : label),
                    subtitle: Text(
                      '${s['pkg']}\n${node['id'] ?? ''}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    isThreeLine: node['id'] != null,
                  );
                }),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => setState(() => _showRaw = !_showRaw),
                  child: Text(_showRaw ? l10n.hideRaw : l10n.showRaw),
                ),
                if (_showRaw)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SelectableText(
                      // 只渲染前面一段：一份錄製可能上百 KB 到數 MB，整份塞進單一 Text 會做一次
                      // 巨大的文字排版，畫面直接卡住。要完整內容用 adb 取檔比在手機上讀實際。
                      _raw.length > kRawPreviewChars
                          ? '${_raw.substring(0, kRawPreviewChars)}\n…（已截斷，完整內容請取檔）'
                          : _raw,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                      ),
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
enum _BallMode { idle, switching, expanded, solution }

class _FloatingBallState extends State<FloatingBall>
    with WidgetsBindingObserver {
  /// 懸浮窗形態的縮放 / 移動走這條（由 OverlayService 註冊在第二引擎上）。
  static const MethodChannel _selfChannel = MethodChannel('x-slayer/overlay');

  _BallMode _modeValue = _BallMode.idle;

  _BallMode get _mode => _modeValue;

  /// 拖去底部 X 丟掉與放手吸邊都只給球：解答小卡也走原生拖曳，但拖它不該冒出 X、也不該
  /// 被吸到邊上。原生分不出視窗現在是哪一種，由這裡告訴它。形態在七處切換，集中在 setter
  /// 通知，免得哪處漏掉。
  set _mode(_BallMode mode) {
    final bool wasBall = _modeValue == _BallMode.idle;
    final bool isBall = mode == _BallMode.idle;
    _modeValue = mode;
    if (wasBall != isBall) {
      _callOverlay(
        () => _selfChannel.invokeMethod<void>(
          'setBallMode',
          <String, bool>{'ball': isBall},
        ),
      );
    }
  }

  /// 展開當下球的位置（dp，螢幕左上角為原點）。
  ///
  /// 拖曳全程交給原生，Flutter 不追蹤座標——要用的時候直接問
  /// `getOverlayPosition()`。實測懸浮窗這側呼叫得到主引擎 channel 上的 method
  /// （第二引擎是 `FlutterEngineGroup.createAndRunEngine` 建的，會自動註冊 plugin），
  /// 所以不需要自己接管拖曳來換取「知道球在哪」。
  Offset _ballAtExpand = Offset.zero;

  /// 放手後要不要自動吸附到邊緣。
  ///
  /// 連點情境通常要關掉：`dispatchGesture` 是派到系統層，目標若落在球底下，那一下會被
  /// 我們自己的懸浮窗吃掉；吸附把球釘在邊緣，剛好讓「目標在邊緣附近」變成高機率情境。
  /// 純截圖情境則留著比較順手。
  ///
  /// 放手後的吸附由原生做（OverlayService.springToEdge，跟著螢幕刷新跑彈簧），這裡只管
  /// 開關，改了要用 [_syncSnapToEdge] 同步過去；收合時落點貼邊仍由 [_collapse] 自己算。
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

  /// 錄製操作流程用。錄的是**別的 App** 的無障礙事件，自己的封包要濾掉。
  StreamSubscription<AccessibilityEvent>? _a11ySub;
  final List<Map<String, dynamic>> _steps = <Map<String, dynamic>>[];
  String? _lastTreeFingerprint;
  bool get _recording => _a11ySub != null;

  String? _lastFromApp;
  StreamSubscription<dynamic>? _sub;

  /// 最近一次 MeowDoku 的盤面與答案。只留色塊編號與顏色——截圖的像素讀完就丟，
  /// 不落檔，也不留在記憶體裡。
  MeowdokuBoard? _board;
  List<int>? _solution;

  /// 解題失敗的原因；有值時小卡改顯示這段文字。
  String? _solveError;

  /// 最近一次向原生問到的螢幕尺寸（dp）。還沒問到之前沿用 [screenSizeDp]——引擎剛建立
  /// 時那個值是對的，只是之後不會跟著轉向更新（理由見 [_refreshScreen]）。
  Size? _screenDp;

  Size get _screen => _screenDp ?? screenSizeDp();

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
    _selfChannel.setMethodCallHandler(_onNativeCall);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _selfChannel.setMethodCallHandler(null);
    _clickTimer?.cancel();
    _a11ySub?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 關閉懸浮球只是把 View 從 WindowManager 拆下來，引擎與 isolate 都留在快取裡，
    // 所以再開一次時 initState 不會重跑，_mode 會沿用上一輪的值（關閉時若正展開著，
    // 下次開啟就會用全螢幕的排版去畫一個球大小的視窗）。OverlayService 每次
    // onStartCommand 都會送一個 appIsResumed，拿它當重新掛載的訊號重置。
    // 光送 resumed 只有第一次收得到——LifecycleChannel 會吞掉跟上一次相同的狀態——所以原生那邊
    // 每次顯示都先送 inactive（見 OverlayService.onStartCommand 的 LOCAL PATCH）。
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
  ///
  /// intent 交給原生發（OverlayService.openHostApp），要跟桌面圖示發的一模一樣：之前用
  /// android_intent_plus 自己組，action 與 package 都跟桌面的不同，主 App 被返回鍵關掉後再按
  /// 「返回 App」，多工畫面就會多出一張卡片。
  Future<void> _openMainApp() async {
    await _collapse();
    _report(_l10n.backToApp);
    await _callOverlay(() => _selfChannel.invokeMethod<void>('openHostApp'));
  }

  Future<void> _onNativeCall(MethodCall call) async {
    if (call.method == 'onDismissed') await _exitCompletely();
  }

  /// 球被丟進底部的 X：收掉手上的工作，再請原生把整個 App 連同行程收掉。
  ///
  /// `exitApp` 不走 [_callOverlay]：原生剛透過同一條 channel 呼叫過來，handler 必定在；
  /// 而 [_callOverlay] 重試完會把例外吞掉，這裡要讓失敗傳回原生，它收到 error 會自己收尾，
  /// 不會留下一顆看不見的球。
  Future<void> _exitCompletely() async {
    _clickTimer?.cancel();
    // 錄到的步驟只在記憶體裡，行程一死就沒了，先落檔。
    if (_recording) await _stopRecording();
    await _selfChannel.invokeMethod<void>('exitApp');
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

  // ── 解 MeowDoku ──

  Future<void> _solveMeowdoku() async {
    final AppLocalizations l10n = _l10n;
    // 面板與球都會被拍進去，而面板正好壓在盤面那個高度。展開時視窗是全螢幕、錨在
    // (0,0)，切到「什麼都不畫」就是一整片透明——直接拍，省掉先收合再拍那一輪搬移。
    setState(() => _mode = _BallMode.switching);
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(kCaptureSettleDelay);
    MeowdokuBoard? board;
    List<int>? solution;
    String? error;
    // 截圖是實體像素、視窗座標是 dp；解出盤面後要把小卡擺在盤面旁邊，得換算。
    double scale = 1;
    try {
      final ScreenCapture shot =
          await FlutterAccessibilityService.takeScreenshot();
      await _refreshScreen();
      scale = shot.width / _screen.width;
      board = readMeowdokuBoard(
        shot.pixels,
        width: shot.width,
        height: shot.height,
        rowBytes: shot.rowBytes,
      );
      final List<List<int>> solutions = solveMeowdoku(board.regions);
      if (solutions.isEmpty) {
        error = l10n.solveNoSolution;
      } else if (solutions.length > 1) {
        error = l10n.solveAmbiguous;
      } else {
        solution = solutions.single;
      }
    } on PlatformException catch (e) {
      error = switch (e.code) {
        // 兩者處置相同：重裝 App 後服務常是「列為啟用但沒連上」，而新加的
        // canTakeScreenshot 也要服務重新綁定、系統重讀 XML 才生效。
        'NO_ACCESS' || 'NOT_CONNECTED' => l10n.screenshotNoAccess,
        'TOO_FREQUENT' => l10n.screenshotTooFrequent,
        'SECURE_WINDOW' => l10n.screenshotSecure,
        'UNSUPPORTED' => l10n.screenshotUnsupported,
        _ => l10n.screenshotFailed('${e.code} ${e.message ?? ''}'),
      };
    } on MeowdokuReadException catch (e) {
      error = switch (e.failure) {
        MeowdokuReadFailure.noGrid => l10n.solveNoGrid,
        MeowdokuReadFailure.gridMismatch => l10n.solveGridMismatch(
          e.expected ?? 0,
          e.found ?? 0,
        ),
        MeowdokuReadFailure.regionMismatch => l10n.solveRegionMismatch(
          e.found ?? 0,
          e.expected ?? 0,
        ),
      };
    } catch (e) {
      // 其餘例外（MissingPluginException、回傳型別不符…）也一定要走到下面把視窗收掉：
      // 停在 switching 的話，全螢幕的透明視窗會吃掉所有點擊，看起來像整台卡死。
      error = l10n.screenshotFailed('$e');
    }
    if (!mounted) return;
    _board = error == null ? board : null;
    _solution = error == null ? solution : null;
    _solveError = error;
    _report(error ?? l10n.logSolved(board!.size));
    try {
      await _showSolutionCard(board, scale);
    } catch (e) {
      // 換尺寸失敗就退回成球，理由同上。
      debugPrint('solution card failed: $e');
      if (mounted) await _collapse();
    }
  }

  /// 把視窗縮成小卡、擺到盤面旁邊。呼叫時視窗必須是 switching（什麼都不畫），
  /// 理由同 [_expand]：改尺寸時 Android 會拉伸舊內容。
  Future<void> _showSolutionCard(MeowdokuBoard? board, double scale) async {
    await _refreshScreen();
    final Size screen = _screen;
    final Size card = _solveError == null && board != null
        ? const Size(
            kSolutionBoardDp + (kSolutionPadDp + kSolutionBorderDp) * 2,
            kSolutionBoardDp +
                (kSolutionPadDp + kSolutionBorderDp) * 2 +
                kSolutionHeaderDp,
          )
        : kSolveErrorCardDp;
    final double x = _onRight ? screen.width - card.width : 0;
    double y;
    if (_solveError == null && board != null) {
      // 優先放盤面正下方，放不下才放上方：蓋到盤面就失去「對照著填」的意義了。
      final double below = board.bottom / scale + 8;
      final double above = board.top / scale - 8 - card.height;
      y = below + card.height <= screen.height - 12 ? below : above;
    } else {
      y = _ballAtExpand.dy + kBallDp - card.height;
    }
    // clamp 的上界比下界小會丟 ArgumentError（螢幕高不到卡片 + 24dp 時）。
    final double maxY = screen.height - card.height - 12;
    y = maxY < 12 ? 12 : y.clamp(12.0, maxY);
    // 開放原生拖曳：擺的位置不一定剛好，蓋到要看的地方時可以自己挪開。
    await Future.wait(<Future<void>>[
      _callOverlay(
        () => FlutterOverlayWindow.resizeOverlay(
          card.width.ceil(),
          card.height.ceil(),
          true,
        ),
      ),
      _moveWindow(x.round(), y.round()),
    ]);
    await Future<void>.delayed(kCollapseRevealDelay);
    if (!mounted) return;
    setState(() => _mode = _BallMode.solution);
  }

  // ── 錄製操作流程 ──
  //
  // 無障礙露出多少完全看目標 App 怎麼寫的（有沒有設 id / contentDescription、用標準元件
  // 還是自繪、Flutter 只給 Semantics…），沒有規格可查、只能實際看。這個錄製器就是「看」
  // 的工具：錄一次、把事件序列落成 JSON，省掉「猜 → 改碼 → 重裝 → 測」那一圈。

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _stopRecording();
      return;
    }
    _steps.clear();
    _lastTreeFingerprint = null;
    _a11ySub = FlutterAccessibilityService.accessStream.listen(_onA11yEvent);
    _report(_l10n.logRecordStart);
    setState(() {});
    await _collapse();
  }

  void _onA11yEvent(AccessibilityEvent e) {
    // 主 App 按「關閉懸浮球」走 stopService，只拆原生 View，不會重跑 initState / dispose、
    // 也不通知 Dart 側——這條訂閱收不到任何訊號。不自己檢查的話，視窗關了它還在收整台裝置
    // 的無障礙事件往記憶體堆，而使用者已經按不到停止鍵，錄到的東西也永遠不會落檔。
    // 同 _clickTimer 的處置。
    _stopIfOverlayGone();
    // 自己的懸浮層與主 App 會製造大量雜訊，濾掉。
    if (e.packageName == null ||
        e.packageName!.startsWith('com.louis.overlay_demo')) {
      return;
    }
    if (_steps.length >= 500) return;
    final bool isScreenChange =
        e.eventType == EventType.typeWindowStateChanged ||
        e.eventType == EventType.typeWindowsChanged;
    // 樹要不要收：只在「換畫面」收的話，實測一整段操作只會拿到一棵。改成看內容指紋，
    // 樹變了就收一次、沒變就跳過——既不會被 contentChanged 洗爆，也不會漏掉新畫面。
    final List<AccessibilityEvent> sub = e.subNodes ?? <AccessibilityEvent>[];
    final String fingerprint =
        '${e.packageName}|${sub.length}|${(e.nodesText ?? <String>[]).take(8).join('~')}';
    final bool treeIsNew =
        sub.isNotEmpty && fingerprint != _lastTreeFingerprint;
    if (treeIsNew) _lastTreeFingerprint = fingerprint;
    _steps.add(<String, dynamic>{
      'at': (e.eventTime ?? DateTime.now()).toIso8601String(),
      'pkg': e.packageName,
      'event': e.eventType?.name,
      'node': _nodeToJson(e),
      // 子樹的文字集合——爬資訊時這欄最有用，原生一直有送、只是上游 Dart 沒暴露。
      if ((e.nodesText ?? <String>[]).isNotEmpty) 'texts': e.nodesText,
      if (isScreenChange || treeIsNew)
        'tree': sub.take(300).map(_nodeToJson).toList(),
    });
  }

  Map<String, dynamic> _nodeToJson(AccessibilityEvent e) {
    final ScreenBounds? b = e.screenBounds;
    return <String, dynamic>{
      if (e.nodeId != null) 'id': e.nodeId,
      if (e.text != null && e.text!.isNotEmpty) 'text': e.text,
      if (e.contentDescription != null && e.contentDescription!.isNotEmpty)
        'desc': e.contentDescription,
      if (b != null) 'bounds': <int?>[b.left, b.top, b.right, b.bottom],
      if (e.isClickable ?? false) 'clickable': true,
      if (e.isScrollable ?? false) 'scrollable': true,
      if (e.isEditable ?? false) 'editable': true,
      if ((e.actions ?? <NodeAction>[]).isNotEmpty)
        'actions': e.actions!.map((NodeAction a) => a.name).toList(),
    };
  }

  /// 懸浮球已經被關掉就自行停止錄製並落檔。
  bool _checkingOverlay = false;
  DateTime _lastOverlayCheck = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _stopIfOverlayGone() async {
    if (_checkingOverlay || _a11ySub == null) return;
    // 節流：這是每一則無障礙事件都會走到的地方，而捲動時事件非常密集。沒有間隔的話
    // 等於在滑動期間持續發 MethodChannel 往返，只為了問一件變動極慢的事。
    final DateTime now = DateTime.now();
    if (now.difference(_lastOverlayCheck) < kOverlayCheckInterval) return;
    _lastOverlayCheck = now;
    _checkingOverlay = true;
    try {
      if (!await FlutterOverlayWindow.isActive()) await _stopRecording();
    } finally {
      _checkingOverlay = false;
    }
  }

  Future<void> _stopRecording() async {
    await _a11ySub?.cancel();
    _a11ySub = null;
    // 內部儲存而非 getExternalStorageDirectory()：這些檔案裝的是**其他 App 的畫面文字**，
    // 放 app-private 的內部目錄，其他工具與備份機制碰不到。debug build 要取出用
    // `adb exec-out run-as com.louis.overlay_demo cat <path>`。
    final Directory dir = await getApplicationDocumentsDirectory();
    final String stamp = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final File f = File('${dir.path}/flow-$stamp.json');
    try {
      await f.writeAsString(const JsonEncoder.withIndent('  ').convert(_steps));
      _report(_l10n.logRecordSaved(f.path, _steps.length));
    } catch (e) {
      // 沒有這層的話，落檔失敗會是一個未捕捉例外：UI 停在舊狀態、使用者看不到任何訊息，
      // 整段錄製無聲消失。
      debugPrint('flow recording save failed: $e');
      if (mounted) setState(() => _clickError = '$e');
    }
    // 清理與落檔分開：合在同一個 try 的話，檔案明明存成功、只是清舊檔失敗，
    // 使用者卻會看到「儲存失敗」。
    await _pruneOldRecordings(dir);
    if (mounted) setState(() {});
  }

  /// 清掉所有錄製檔。內容是其他 App 的畫面文字，能隨手清掉才不用等自動清理。
  Future<void> _clearRecordings() async {
    try {
      final Directory dir = await getApplicationDocumentsDirectory();
      final List<File> files = dir
          .listSync()
          .whereType<File>()
          .where((File f) => f.path.contains('/flow-'))
          .toList();
      for (final File f in files) {
        await f.delete();
      }
      _report(_l10n.logRecordingsCleared(files.length));
    } catch (e) {
      debugPrint('clear recordings failed: $e');
      if (mounted) setState(() => _clickError = '$e');
    }
  }

  /// 只留最近幾份。內容是其他 App 的畫面文字，無限累積等於在裝置上堆明文。
  Future<void> _pruneOldRecordings(Directory dir) async {
    final List<File> files =
        dir
            .listSync()
            .whereType<File>()
            .where((File f) => f.path.contains('/flow-'))
            .toList()
          ..sort((File a, File b) => b.path.compareTo(a.path));
    for (final File old in files.skip(kMaxRecordingFiles)) {
      try {
        await old.delete();
      } catch (_) {
        // 刪不掉就算了，不值得為此讓落檔失敗。
      }
    }
  }

  // ── 展開 / 收合 ──

  /// 視窗是從自己被錨定的那一角長出來的，球貼在左緣時面板會整片長到畫面外。
  /// 展開時改成讓視窗鋪滿螢幕、由 Flutter 依 `_onRight` 決定面板靠哪邊，
  /// 順便得到「點空白處收合」的行為。
  void _syncSnapToEdge() {
    _callOverlay(
      () => _selfChannel.invokeMethod<void>(
        'setSnapToEdge',
        <String, bool>{'enabled': _snapEnabled},
      ),
    );
  }

  Future<void> _expand() async {
    // 原生的吸邊彈簧不必在這裡停：點下去那一刻（ACTION_DOWN）原生就停了，切出球的形態
    // （setBallMode）時也會再停一次。
    final OverlayPosition pos = await FlutterOverlayWindow.getOverlayPosition();
    // 展開後的面板版面（靠哪邊、高度上限）在 build 裡同步讀 _screen，得在這裡先更新。
    await _refreshScreen();
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
    // 先切成 switching、之後才 await：等待期間面板若還畫著、點得到，連點兩下就會疊出
    // 兩次收合。
    setState(() => _mode = _BallMode.switching);
    await _refreshScreen();
    if (!mounted) return;
    // 原生的吸附動畫關掉了，改在這裡自己吸附：收合本來就要指定落點，順手貼到最近的邊。
    // 吸附關掉時就原地放回去，不要偷偷把球挪走。
    final int x = _snapEnabled
        ? (_onRight ? (_screen.width - kBallDp).round() : 0)
        : _ballAtExpand.dx.round();
    final int y = _ballAtExpand.dy.round();
    _ballAtExpand = Offset(x.toDouble(), y.toDouble());
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

  /// 向原生要目前的螢幕尺寸，更新 [_screenDp]。
  ///
  /// 不能只靠 [screenSizeDp]：懸浮層引擎掛在 Service 底下、沒有 Activity，而 Flutter
  /// embedding 只在找得到 Activity 時才把螢幕尺寸送進引擎（Flutter 3.38.10 / engine
  /// cafcda5721 的 ViewUtils.calculateMaximumDisplayMetrics 反組譯確認），所以
  /// `display.size` 會停在引擎建立當下的方向。實測引擎在橫向建立、轉回直向後，吸右門檻（球心過半寬）變成
  /// 487dp，直向卻最寬只有 417dp，往右拖一律吸回左邊；反過來直向建立、轉橫向，則會吸到
  /// 畫面中間。轉向時 Dart 這側也收不到通知（見 OverlayService.onConfigurationChanged
  /// 的註解），所以在每個要用到尺寸的動作開頭現問一次，而不是等推播。
  /// 問不到（channel 正在重新掛載等）就沿用上一個值。
  Future<void> _refreshScreen() async {
    // 一律接住、沿用舊值：這裡失敗只是吸邊方向可能判錯，不值得讓展開／收合整段中斷。
    try {
      final Map<dynamic, dynamic>? px = await _selfChannel
          .invokeMapMethod<dynamic, dynamic>('getScreenSize');
      if (px == null) return;
      // 跟 screenSizeDp 同一套換算：dpr 不隨轉向改變，兩邊才對得起來。
      final double dpr = WidgetsBinding
          .instance
          .platformDispatcher
          .views
          .first
          .display
          .devicePixelRatio;
      _screenDp = Size(
        (px['width'] as int) / dpr,
        (px['height'] as int) / dpr,
      );
    } catch (e) {
      debugPrint('getScreenSize failed: $e');
    }
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
      case _BallMode.solution:
        return _buildSolution();
    }
  }

  /// 解答小卡：點一下任何地方就收回成球。
  Widget _buildSolution() {
    final MeowdokuBoard? board = _board;
    final List<int>? solution = _solution;
    final String? error = _solveError;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: _collapse,
      child: Container(
        padding: const EdgeInsets.all(kSolutionPadDp),
        // 不加陰影：視窗跟卡片一樣大，陰影會被視窗邊界切掉。
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: scheme.outlineVariant,
            width: kSolutionBorderDp,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              height: kSolutionHeaderDp,
              child: Row(
                children: <Widget>[
                  Text(
                    error == null ? _l10n.solutionTitle : _l10n.solveFailedTitle,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.close, size: 16),
                ],
              ),
            ),
            if (error != null || board == null || solution == null)
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    error ?? '',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              )
            else
              // 填滿剩下的空間而不是寫死 kSolutionBoardDp：視窗尺寸是 dp 換成整數 px，
              // 捨入後可能比算的小零點幾個像素，寫死就會 overflow。
              Expanded(
                child: CustomPaint(painter: _MiniBoardPainter(board, solution)),
              ),
          ],
        ),
      ),
    );
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
    return GestureDetector(
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
                      _syncSnapToEdge();
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
                  _PanelButton(
                    label: _l10n.solveMeowdoku,
                    filled: true,
                    onTap: _solveMeowdoku,
                  ),
                  _PanelButton(
                    label: _recording
                        ? _l10n.recordStop(_steps.length)
                        : _l10n.recordFlow,
                    filled: _recording,
                    onTap: _toggleRecording,
                  ),
                  _PanelButton(
                    label: _l10n.clearRecordings,
                    // 錄製中不給清，否則會刪到正要寫入的那一份。
                    onTap: _recording ? null : _clearRecordings,
                  ),
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

/// 縮小版盤面：沿用遊戲的色塊配色，貓的位置畫成白邊深色圓點，任何底色上都看得清楚。
class _MiniBoardPainter extends CustomPainter {
  _MiniBoardPainter(this.board, this.solution);

  final MeowdokuBoard board;
  final List<int> solution;

  @override
  void paint(Canvas canvas, Size size) {
    final double cell = size.shortestSide / board.size;
    final Paint fill = Paint();
    for (int r = 0; r < board.size; r++) {
      for (int c = 0; c < board.size; c++) {
        fill.color = Color(board.regionColors[board.regions[r][c]]);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(c * cell + 0.5, r * cell + 0.5, cell - 1, cell - 1),
            const Radius.circular(2),
          ),
          fill,
        );
      }
    }
    final Paint ring = Paint()..color = Colors.white;
    final Paint dot = Paint()..color = const Color(0xFF222222);
    for (int r = 0; r < solution.length; r++) {
      final Offset center = Offset((solution[r] + 0.5) * cell, (r + 0.5) * cell);
      canvas.drawCircle(center, cell * 0.34, ring);
      canvas.drawCircle(center, cell * 0.24, dot);
    }
  }

  @override
  bool shouldRepaint(_MiniBoardPainter oldDelegate) =>
      oldDelegate.board != board || oldDelegate.solution != solution;
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
