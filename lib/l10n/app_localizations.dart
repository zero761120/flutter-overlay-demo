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
