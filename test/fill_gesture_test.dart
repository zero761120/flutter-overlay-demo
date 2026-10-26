import 'package:flutter_accessibility_service/gesture_description.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overlay_demo/main.dart';

void main() {
  test('幫點的連點兩下：同一點、先後兩下，間隔落在系統的連點判定內', () {
    final GestureDescription g = doubleTapAt(const GesturePoint(120, 340));
    expect(g.strokes, hasLength(2));
    for (final GestureStroke s in g.strokes) {
      expect(s.path, hasLength(1));
      expect(s.path.single.x, 120);
      expect(s.path.single.y, 340);
      expect(s.duration, greaterThan(0));
    }
    final GestureStroke first = g.strokes[0];
    final GestureStroke second = g.strokes[1];
    // 兩下同時按（startTime 相同）會變成兩指點擊；放開到再按下要介於 Android
    // ViewConfiguration 的 DOUBLE_TAP_MIN_TIME（40ms）與 DOUBLE_TAP_TIMEOUT（300ms）之間。
    final int gap = second.startTime - (first.startTime + first.duration);
    expect(gap, inInclusiveRange(40, 300));
  });

  test('兩格之間停得比連點判定久，下一格的第一下才不會跟上一格湊成連點', () {
    expect(kFillGestureGap.inMilliseconds, greaterThan(300));
  });
}
