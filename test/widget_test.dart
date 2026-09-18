import 'package:flutter_test/flutter_test.dart';

import 'package:overlay_demo/main.dart';

void main() {
  testWidgets('主畫面列出權限狀態與操作按鈕', (WidgetTester tester) async {
    await tester.pumpWidget(const DemoApp());
    await tester.pump();

    expect(find.text('懸浮窗權限'), findsOneWidget);
    expect(find.text('懸浮球運行中'), findsOneWidget);
    expect(find.text('授予懸浮窗權限'), findsOneWidget);
    expect(find.text('顯示懸浮球'), findsOneWidget);
    expect(find.text('關閉懸浮球'), findsOneWidget);
  });
}
