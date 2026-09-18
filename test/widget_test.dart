import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:overlay_demo/main.dart';

void main() {
  testWidgets('主畫面依系統語系顯示中文或英文', (WidgetTester tester) async {
    // DemoApp 自己建 MaterialApp、沒有對外開 locale 參數，所以從 platformDispatcher
    // 這一層換語系，順便也就驗到了「跟隨系統」這個行為本身。
    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(const DemoApp());
    await tester.pump();

    expect(find.text('懸浮窗權限'), findsOneWidget);
    expect(find.text('顯示懸浮球'), findsOneWidget);
    expect(find.text('動作紀錄'), findsOneWidget);

    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('en')];
    await tester.pumpWidget(const DemoApp());
    await tester.pump();

    expect(find.text('Overlay permission'), findsOneWidget);
    expect(find.text('Show floating ball'), findsOneWidget);
    expect(find.text('Activity log'), findsOneWidget);
  });
}
