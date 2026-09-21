// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '懸浮球 Demo';

  @override
  String get permOverlay => '懸浮窗權限';

  @override
  String get permOverlayGrant => '授予懸浮窗權限';

  @override
  String get permA11y => '無障礙服務（模擬點擊 / 截圖）';

  @override
  String get permA11yGrant => '啟用無障礙服務';

  @override
  String get ballRunning => '懸浮球運行中';

  @override
  String get ballShow => '顯示懸浮球';

  @override
  String get ballClose => '關閉懸浮球';

  @override
  String get sendToBall => '傳訊息給懸浮球';

  @override
  String get actionLog => '動作紀錄';

  @override
  String get clear => '清空';

  @override
  String get actionLogEmpty => '（懸浮球做了什麼會記在這裡）';

  @override
  String helloFromApp(String time) {
    return '主 App 說哈囉 $time';
  }

  @override
  String get menuTitle => '懸浮選單';

  @override
  String get targetUnset => '尚未設定點擊位置';

  @override
  String targetAt(String x, String y) {
    return '點擊位置 ($x, $y)';
  }

  @override
  String get a11yHint => '需先到「設定 → 協助工具」啟用本 App 的無障礙服務';

  @override
  String get dispatchFailed => '派送失敗：請到「設定 → 協助工具」把本 App 的服務關掉再重新開啟';

  @override
  String fromApp(String message) {
    return '主 App：$message';
  }

  @override
  String snapEdge(String state) {
    return '吸附邊緣：$state';
  }

  @override
  String get on => '開';

  @override
  String get off => '關';

  @override
  String get setTarget => '設定點擊位置';

  @override
  String get startClicking => '開始連點';

  @override
  String get stopClicking => '停止連點';

  @override
  String get screenshot => '螢幕截圖';

  @override
  String get backToApp => '返回 App';

  @override
  String get pickHint => '點一下要連點的位置';

  @override
  String logSetTarget(String x, String y) {
    return '設定點擊位置 ($x, $y)';
  }

  @override
  String logStartClicking(int ms) {
    return '開始連點（間隔 ${ms}ms）';
  }

  @override
  String get recordFlow => '錄製操作流程';

  @override
  String recordStop(int n) {
    return '停止錄製（$n 步）';
  }

  @override
  String get logRecordStart => '開始錄製操作流程';

  @override
  String logRecordSaved(String path, int n) {
    return '已存檔：$path（$n 步）';
  }

  @override
  String get clearRecordings => '清除錄製檔';

  @override
  String logRecordingsCleared(int n) {
    return '已清除 $n 份錄製檔';
  }

  @override
  String get recordings => '錄製檔';

  @override
  String get recordingsEmpty => '尚無錄製檔';

  @override
  String stepsCount(int n) {
    return '$n 步';
  }

  @override
  String get showRaw => '顯示原始 JSON';

  @override
  String get hideRaw => '收合原始 JSON';

  @override
  String get clicksOnly => '只看點擊';

  @override
  String get allSteps => '全部步驟';
}
