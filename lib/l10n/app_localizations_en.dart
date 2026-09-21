// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Floating Ball Demo';

  @override
  String get permOverlay => 'Overlay permission';

  @override
  String get permOverlayGrant => 'Grant overlay permission';

  @override
  String get permA11y => 'Accessibility service (tap / screenshot)';

  @override
  String get permA11yGrant => 'Enable accessibility service';

  @override
  String get ballRunning => 'Floating ball running';

  @override
  String get ballShow => 'Show floating ball';

  @override
  String get ballClose => 'Close floating ball';

  @override
  String get sendToBall => 'Send message to ball';

  @override
  String get actionLog => 'Activity log';

  @override
  String get clear => 'Clear';

  @override
  String get actionLogEmpty => '(what the ball does shows up here)';

  @override
  String helloFromApp(String time) {
    return 'Hello from the app $time';
  }

  @override
  String get menuTitle => 'Floating menu';

  @override
  String get targetUnset => 'No tap target set';

  @override
  String targetAt(String x, String y) {
    return 'Tap target ($x, $y)';
  }

  @override
  String get a11yHint =>
      'Enable this app\'s accessibility service in Settings → Accessibility first';

  @override
  String get dispatchFailed =>
      'Dispatch failed: turn this app\'s accessibility service off and on again in Settings → Accessibility';

  @override
  String fromApp(String message) {
    return 'App: $message';
  }

  @override
  String snapEdge(String state) {
    return 'Snap to edge: $state';
  }

  @override
  String get on => 'on';

  @override
  String get off => 'off';

  @override
  String get setTarget => 'Set tap target';

  @override
  String get startClicking => 'Start auto tap';

  @override
  String get stopClicking => 'Stop auto tap';

  @override
  String get screenshot => 'Screenshot';

  @override
  String get backToApp => 'Back to app';

  @override
  String get pickHint => 'Tap where you want the auto tap';

  @override
  String logSetTarget(String x, String y) {
    return 'Tap target set ($x, $y)';
  }

  @override
  String logStartClicking(int ms) {
    return 'Auto tap started (every ${ms}ms)';
  }

  @override
  String get recordFlow => 'Record a flow';

  @override
  String recordStop(int n) {
    return 'Stop recording ($n steps)';
  }

  @override
  String get logRecordStart => 'Flow recording started';

  @override
  String logRecordSaved(String path, int n) {
    return 'Saved: $path ($n steps)';
  }

  @override
  String get clearRecordings => 'Clear recordings';

  @override
  String logRecordingsCleared(int n) {
    return 'Cleared $n recording(s)';
  }

  @override
  String get recordings => 'Recordings';

  @override
  String get recordingsEmpty => 'No recordings yet';

  @override
  String stepsCount(int n) {
    return '$n steps';
  }

  @override
  String get showRaw => 'Show raw JSON';

  @override
  String get hideRaw => 'Hide raw JSON';

  @override
  String get clicksOnly => 'Taps only';

  @override
  String get allSteps => 'All steps';
}
