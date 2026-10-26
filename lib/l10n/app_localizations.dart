import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'懸浮球 Demo'**
  String get appTitle;

  /// No description provided for @permOverlay.
  ///
  /// In zh, this message translates to:
  /// **'懸浮窗權限'**
  String get permOverlay;

  /// No description provided for @permOverlayGrant.
  ///
  /// In zh, this message translates to:
  /// **'授予懸浮窗權限'**
  String get permOverlayGrant;

  /// No description provided for @permA11y.
  ///
  /// In zh, this message translates to:
  /// **'無障礙服務（模擬點擊 / 截圖）'**
  String get permA11y;

  /// No description provided for @permA11yGrant.
  ///
  /// In zh, this message translates to:
  /// **'啟用無障礙服務'**
  String get permA11yGrant;

  /// No description provided for @ballRunning.
  ///
  /// In zh, this message translates to:
  /// **'懸浮球運行中'**
  String get ballRunning;

  /// No description provided for @ballShow.
  ///
  /// In zh, this message translates to:
  /// **'顯示懸浮球'**
  String get ballShow;

  /// No description provided for @ballClose.
  ///
  /// In zh, this message translates to:
  /// **'關閉懸浮球'**
  String get ballClose;

  /// No description provided for @sendToBall.
  ///
  /// In zh, this message translates to:
  /// **'傳訊息給懸浮球'**
  String get sendToBall;

  /// No description provided for @actionLog.
  ///
  /// In zh, this message translates to:
  /// **'動作紀錄'**
  String get actionLog;

  /// No description provided for @clear.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get clear;

  /// No description provided for @actionLogEmpty.
  ///
  /// In zh, this message translates to:
  /// **'（懸浮球做了什麼會記在這裡）'**
  String get actionLogEmpty;

  /// No description provided for @helloFromApp.
  ///
  /// In zh, this message translates to:
  /// **'主 App 說哈囉 {time}'**
  String helloFromApp(String time);

  /// No description provided for @menuTitle.
  ///
  /// In zh, this message translates to:
  /// **'懸浮選單'**
  String get menuTitle;

  /// No description provided for @targetUnset.
  ///
  /// In zh, this message translates to:
  /// **'尚未設定點擊位置'**
  String get targetUnset;

  /// No description provided for @targetAt.
  ///
  /// In zh, this message translates to:
  /// **'點擊位置 ({x}, {y})'**
  String targetAt(String x, String y);

  /// No description provided for @a11yHint.
  ///
  /// In zh, this message translates to:
  /// **'需先到「設定 → 協助工具」啟用本 App 的無障礙服務'**
  String get a11yHint;

  /// No description provided for @dispatchFailed.
  ///
  /// In zh, this message translates to:
  /// **'派送失敗：請到「設定 → 協助工具」把本 App 的服務關掉再重新開啟'**
  String get dispatchFailed;

  /// No description provided for @fromApp.
  ///
  /// In zh, this message translates to:
  /// **'主 App：{message}'**
  String fromApp(String message);

  /// No description provided for @snapEdge.
  ///
  /// In zh, this message translates to:
  /// **'吸附邊緣：{state}'**
  String snapEdge(String state);

  /// No description provided for @on.
  ///
  /// In zh, this message translates to:
  /// **'開'**
  String get on;

  /// No description provided for @off.
  ///
  /// In zh, this message translates to:
  /// **'關'**
  String get off;

  /// No description provided for @setTarget.
  ///
  /// In zh, this message translates to:
  /// **'設定點擊位置'**
  String get setTarget;

  /// No description provided for @startClicking.
  ///
  /// In zh, this message translates to:
  /// **'開始連點'**
  String get startClicking;

  /// No description provided for @stopClicking.
  ///
  /// In zh, this message translates to:
  /// **'停止連點'**
  String get stopClicking;

  /// No description provided for @screenshot.
  ///
  /// In zh, this message translates to:
  /// **'螢幕截圖'**
  String get screenshot;

  /// No description provided for @backToApp.
  ///
  /// In zh, this message translates to:
  /// **'返回 App'**
  String get backToApp;

  /// No description provided for @pickHint.
  ///
  /// In zh, this message translates to:
  /// **'點一下要連點的位置'**
  String get pickHint;

  /// No description provided for @logSetTarget.
  ///
  /// In zh, this message translates to:
  /// **'設定點擊位置 ({x}, {y})'**
  String logSetTarget(String x, String y);

  /// No description provided for @logStartClicking.
  ///
  /// In zh, this message translates to:
  /// **'開始連點（間隔 {ms}ms）'**
  String logStartClicking(int ms);

  /// No description provided for @recordFlow.
  ///
  /// In zh, this message translates to:
  /// **'錄製操作流程'**
  String get recordFlow;

  /// No description provided for @recordStop.
  ///
  /// In zh, this message translates to:
  /// **'停止錄製（{n} 步）'**
  String recordStop(int n);

  /// No description provided for @logRecordStart.
  ///
  /// In zh, this message translates to:
  /// **'開始錄製操作流程'**
  String get logRecordStart;

  /// No description provided for @logRecordSaved.
  ///
  /// In zh, this message translates to:
  /// **'已存檔：{path}（{n} 步）'**
  String logRecordSaved(String path, int n);

  /// No description provided for @clearRecordings.
  ///
  /// In zh, this message translates to:
  /// **'清除錄製檔'**
  String get clearRecordings;

  /// No description provided for @logRecordingsCleared.
  ///
  /// In zh, this message translates to:
  /// **'已清除 {n} 份錄製檔'**
  String logRecordingsCleared(int n);

  /// No description provided for @recordings.
  ///
  /// In zh, this message translates to:
  /// **'錄製檔'**
  String get recordings;

  /// No description provided for @recordingsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'尚無錄製檔'**
  String get recordingsEmpty;

  /// No description provided for @stepsCount.
  ///
  /// In zh, this message translates to:
  /// **'{n} 步'**
  String stepsCount(int n);

  /// No description provided for @showRaw.
  ///
  /// In zh, this message translates to:
  /// **'顯示原始 JSON'**
  String get showRaw;

  /// No description provided for @hideRaw.
  ///
  /// In zh, this message translates to:
  /// **'收合原始 JSON'**
  String get hideRaw;

  /// No description provided for @clicksOnly.
  ///
  /// In zh, this message translates to:
  /// **'只看點擊'**
  String get clicksOnly;

  /// No description provided for @allSteps.
  ///
  /// In zh, this message translates to:
  /// **'全部步驟'**
  String get allSteps;

  /// No description provided for @solveMeowdoku.
  ///
  /// In zh, this message translates to:
  /// **'解題：貓咪在哪裡'**
  String get solveMeowdoku;

  /// No description provided for @solutionTitle.
  ///
  /// In zh, this message translates to:
  /// **'解答'**
  String get solutionTitle;

  /// No description provided for @solveFailedTitle.
  ///
  /// In zh, this message translates to:
  /// **'解不出來'**
  String get solveFailedTitle;

  /// No description provided for @solveNoGrid.
  ///
  /// In zh, this message translates to:
  /// **'畫面上找不到盤面，請在關卡畫面再試一次'**
  String get solveNoGrid;

  /// No description provided for @solveGridMismatch.
  ///
  /// In zh, this message translates to:
  /// **'盤面辨識有誤：找到 {rows} 行、{cols} 列'**
  String solveGridMismatch(int rows, int cols);

  /// No description provided for @solveRegionMismatch.
  ///
  /// In zh, this message translates to:
  /// **'色塊辨識有誤：找到 {found} 種顏色，應該是 {expected} 種'**
  String solveRegionMismatch(int found, int expected);

  /// No description provided for @solveNoSolution.
  ///
  /// In zh, this message translates to:
  /// **'照辨識結果無解，可能有顏色讀錯了'**
  String get solveNoSolution;

  /// No description provided for @solveAmbiguous.
  ///
  /// In zh, this message translates to:
  /// **'照辨識結果不只一組解，可能有格子讀錯了'**
  String get solveAmbiguous;

  /// No description provided for @screenshotNoAccess.
  ///
  /// In zh, this message translates to:
  /// **'無障礙服務尚未就緒（App 更新後常見）：請到「設定 → 協助工具」把本 App 的服務關掉再重新開啟'**
  String get screenshotNoAccess;

  /// No description provided for @screenshotTooFrequent.
  ///
  /// In zh, this message translates to:
  /// **'截圖太頻繁，請稍候再試'**
  String get screenshotTooFrequent;

  /// No description provided for @screenshotSecure.
  ///
  /// In zh, this message translates to:
  /// **'這個畫面禁止截圖'**
  String get screenshotSecure;

  /// No description provided for @screenshotUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'需要 Android 11 以上'**
  String get screenshotUnsupported;

  /// No description provided for @screenshotFailed.
  ///
  /// In zh, this message translates to:
  /// **'截圖失敗：{reason}'**
  String screenshotFailed(String reason);

  /// No description provided for @logSolved.
  ///
  /// In zh, this message translates to:
  /// **'解出 {n}×{n} 盤面'**
  String logSolved(int n);

  /// No description provided for @fillSolution.
  ///
  /// In zh, this message translates to:
  /// **'幫點'**
  String get fillSolution;

  /// No description provided for @fillBoardChanged.
  ///
  /// In zh, this message translates to:
  /// **'盤面跟剛才解的不一樣，請重新解題'**
  String get fillBoardChanged;

  /// No description provided for @fillWrongCat.
  ///
  /// In zh, this message translates to:
  /// **'第 {row} 行第 {col} 列看起來有貓，但不在答案上——多半是讀錯了。確認盤面後再解一次'**
  String fillWrongCat(int row, int col);

  /// No description provided for @logFilled.
  ///
  /// In zh, this message translates to:
  /// **'幫點完成：放了 {n} 隻貓'**
  String logFilled(int n);

  /// No description provided for @logFillStopped.
  ///
  /// In zh, this message translates to:
  /// **'幫點中途停止：懸浮球被關掉了（已放 {n} 隻）'**
  String logFillStopped(int n);

  /// No description provided for @fillLeftApp.
  ///
  /// In zh, this message translates to:
  /// **'幫點中途停止：畫面換到別的 App 了（已放 {n} 隻）'**
  String fillLeftApp(int n);

  /// No description provided for @fillCancelled.
  ///
  /// In zh, this message translates to:
  /// **'幫點中途停止：有一下點擊被系統取消了（已放 {n} 隻）。點擊進行中碰到螢幕可能會這樣；一直發生的話，到「設定 → 協助工具」把本 App 的服務關掉再開'**
  String fillCancelled(int n);

  /// No description provided for @fillNoFront.
  ///
  /// In zh, this message translates to:
  /// **'幫點停止：問不到目前前景是哪個 App，為了不點到別的地方先停下（已放 {n} 隻）'**
  String fillNoFront(int n);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
