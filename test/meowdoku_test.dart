import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:overlay_demo/meowdoku.dart';

/// 第 10 關的實際盤面（從實機截圖讀出、人工逐行對過），實機照解答填入確認正解。
const List<String> kLevel10 = <String>[
  'AAAAAAABBBBB',
  'ACCACCCCBBBB',
  'ADCCCCEEBBBB',
  'ADCCDEEEEEEE',
  'ADDDDDDDDFEE',
  'GGHHHHHHDFFE',
  'GGGGGHGDDFDE',
  'GGIIGGGDDFDD',
  'IIIDDDDDDDDD',
  'IIIDDDDDDJDD',
  'IIKKDKJJJJLD',
  'IIKKKKJJJLLL',
];

List<List<int>> parseRegions(List<String> rows) => rows
    .map((String r) => r.codeUnits.map((int c) => c - 65).toList())
    .toList();

const List<int> kBackground = <int>[246, 242, 239];
const List<List<int>> kRegionRgb = <List<int>>[
  <int>[72, 138, 88],
  <int>[235, 159, 225],
  <int>[159, 112, 80],
  <int>[156, 211, 134],
  <int>[88, 117, 161],
  <int>[198, 165, 54],
  <int>[171, 197, 228],
  <int>[245, 218, 143],
];

/// 用遊戲的版面語彙畫一張假截圖：頁面底色、上方的標題與規則卡片、白底盤面、下方按鈕。
/// [padding] 讓每列尾端多出幾個 byte，驗證有照 rowBytes 走而不是假設 width * 4。
class FakeScreen {
  FakeScreen({this.width = 720, this.height = 1400, this.padding = 16})
    : rowBytes = width * 4 + padding {
    pixels = Uint8List(rowBytes * height);
    fill(0, 0, width, height, kBackground);
  }

  final int width;
  final int height;
  final int padding;
  final int rowBytes;
  late final Uint8List pixels;

  void fill(int x0, int y0, int x1, int y1, List<int> rgb) {
    for (int y = y0; y < y1; y++) {
      for (int x = x0; x < x1; x++) {
        final int i = y * rowBytes + x * 4;
        pixels[i] = rgb[0];
        pixels[i + 1] = rgb[1];
        pixels[i + 2] = rgb[2];
        pixels[i + 3] = 255;
      }
    }
  }

  void circle(int cx, int cy, int r, List<int> rgb) {
    for (int y = cy - r; y < cy + r; y++) {
      for (int x = cx - r; x < cx + r; x++) {
        if ((x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r) {
          fill(x, y, x + 1, y + 1, rgb);
        }
      }
    }
  }

  /// 遊戲裡「打叉」的樣子：白色粗線，從格子約兩成畫到八成，端點是圓頭。
  /// 線寬取實機量到的約一成二（第 1642 關截圖：格子 95px、線寬約 12px）。
  void cross(int x0, int y0, int cell) {
    const List<int> white = <int>[255, 255, 255];
    final int stroke = (cell * 0.06).round();
    for (double t = 0.2; t <= 0.8; t += 0.01) {
      final int a = (cell * t).round();
      circle(x0 + a, y0 + a, stroke, white);
      circle(x0 + cell - a, y0 + a, stroke, white);
    }
  }

  /// 遊戲裡的貓頭：黑白兩色、幾乎蓋滿中央，耳朵頂到上緣附近。
  void cat(int x0, int y0, int cell) {
    final int c = cell ~/ 2;
    circle(x0 + c, y0 + c + cell ~/ 12, (cell * 0.38).round(), <int>[30, 30, 30]);
    circle(x0 + c, y0 + c + cell ~/ 6, (cell * 0.25).round(), <int>[245, 245, 245]);
    circle(x0 + cell * 3 ~/ 10, y0 + cell * 2 ~/ 10, cell ~/ 10, <int>[30, 30, 30]);
    circle(x0 + cell * 7 ~/ 10, y0 + cell * 2 ~/ 10, cell ~/ 10, <int>[30, 30, 30]);
  }

  /// 畫一個 n×n 盤面，回傳每格的左上角，方便在上面加東西。
  List<List<List<int>>> board(
    List<List<int>> regions, {
    int originX = 20,
    int originY = 420,
    int cell = 80,
    int gap = 6,
    List<List<int>> colors = kRegionRgb,
  }) {
    final int n = regions.length;
    final int span = n * cell + (n - 1) * gap;
    fill(originX - 10, originY - 10, originX + span + 10, originY + span + 10, <int>[
      255,
      255,
      255,
    ]);
    final List<List<List<int>>> corners = <List<List<int>>>[];
    for (int r = 0; r < n; r++) {
      final List<List<int>> line = <List<int>>[];
      for (int c = 0; c < n; c++) {
        final int x = originX + c * (cell + gap);
        final int y = originY + r * (cell + gap);
        fill(x, y, x + cell, y + cell, colors[regions[r][c]]);
        line.add(<int>[x, y]);
      }
      corners.add(line);
    }
    return corners;
  }

  void decorations() {
    // 標題文字、三張規則卡片、底部兩顆按鈕：有色但湊不出等距的一整排格子。
    fill(250, 60, 470, 100, <int>[140, 90, 80]);
    for (int i = 0; i < 3; i++) {
      fill(20 + i * 230, 200, 230 + i * 230, 300, <int>[250, 236, 222]);
      fill(40 + i * 230, 220, 90 + i * 230, 280, <int>[160, 110, 80]);
    }
    circle(220, 1250, 50, <int>[255, 255, 255]);
    circle(500, 1250, 50, <int>[255, 255, 255]);
    circle(220, 1250, 20, <int>[60, 60, 60]);
  }
}

bool _sameList(List<int> a, List<int> b) =>
    a.length == b.length &&
    <int>[for (int i = 0; i < a.length; i++) i].every((int i) => a[i] == b[i]);

/// 8×8、兩行四列一塊，共 8 個色塊。
final List<List<int>> kEightByEight = List<List<int>>.generate(
  8,
  (int r) => List<int>.generate(8, (int c) => (r ~/ 2) * 2 + c ~/ 4),
);

void main() {
  group('solveMeowdoku', () {
    test('第 10 關解出實機驗證過的唯一解', () {
      expect(solveMeowdoku(parseRegions(kLevel10)), <List<int>>[
        <int>[6, 8, 4, 7, 1, 10, 5, 0, 2, 9, 3, 11],
      ]);
    });

    test('解出來的位置滿足全部規則', () {
      final List<List<int>> regions = parseRegions(kLevel10);
      final List<int> cols = solveMeowdoku(regions).single;
      expect(cols.toSet().length, 12, reason: '每列一隻');
      expect(
        <int>{for (int r = 0; r < 12; r++) regions[r][cols[r]]}.length,
        12,
        reason: '每個色塊一隻',
      );
      for (int r = 1; r < 12; r++) {
        expect((cols[r] - cols[r - 1]).abs(), greaterThan(1), reason: '斜角不相鄰');
      }
    });

    test('無解時回空：兩個色塊都只在同一列', () {
      // 色塊 0 只有 (0,0)、色塊 1 只有 (1,0)，兩隻都得放第 0 列。
      final List<List<int>> regions = <List<int>>[
        <int>[0, 2, 2, 2],
        <int>[1, 2, 3, 3],
        <int>[2, 2, 3, 3],
        <int>[2, 3, 3, 3],
      ];
      expect(solveMeowdoku(regions), isEmpty);
    });

    test('不只一組解時找到第二組就停', () {
      // 每一行自成一個色塊，等於只剩「行列各一、不相鄰」：4×4 恰好兩組解。
      final List<List<int>> regions = List<List<int>>.generate(
        4,
        (int r) => List<int>.filled(4, r),
      );
      expect(solveMeowdoku(regions), hasLength(2));
      expect(solveMeowdoku(regions, limit: 10), <List<int>>[
        <int>[1, 3, 0, 2],
        <int>[2, 0, 3, 1],
      ]);
    });

    test('第 10 關任一格被讀成相鄰色塊，都不會得到「唯一但錯誤」的解', () {
      // 這種誤讀顏色種類數不變、讀盤那關擋不到；擋它的是「不只一組解就當讀錯」。
      // 162 種讀法中 42 種只取第一組會是錯答案，它們全都不只一組解。
      final List<List<int>> regions = parseRegions(kLevel10);
      const List<int> right = <int>[6, 8, 4, 7, 1, 10, 5, 0, 2, 9, 3, 11];
      int misreads = 0;
      int ambiguous = 0;
      for (int r = 0; r < 12; r++) {
        for (int c = 0; c < 12; c++) {
          final Set<int> neighbours = <int>{
            for (final (int dr, int dc) in <(int, int)>[(-1, 0), (1, 0), (0, -1), (0, 1)])
              if (r + dr >= 0 && r + dr < 12 && c + dc >= 0 && c + dc < 12)
                regions[r + dr][c + dc],
          }..remove(regions[r][c]);
          for (final int other in neighbours) {
            final List<List<int>> misread = <List<int>>[
              for (final List<int> row in regions) List<int>.of(row),
            ];
            misread[r][c] = other;
            if (misread.expand((List<int> row) => row).toSet().length != 12) {
              continue; // 色塊整個消失的那種，讀盤時就會報 regionMismatch。
            }
            misreads++;
            final List<List<int>> solutions = solveMeowdoku(misread);
            if (solutions.length == 2) ambiguous++;
            expect(
              solutions.length != 1 || _sameList(solutions.single, right),
              isTrue,
              reason: '($r,$c) 讀成色塊 $other 時得到唯一但錯誤的解',
            );
          }
        }
      }
      expect(misreads, 162);
      expect(ambiguous, greaterThanOrEqualTo(42));
    });
  });

  group('readMeowdokuBoard', () {
    test('在有標題、卡片、按鈕的畫面裡找到盤面並讀出色塊', () {
      final FakeScreen screen = FakeScreen()..decorations();
      screen.board(kEightByEight);
      final MeowdokuBoard board = readMeowdokuBoard(
        screen.pixels,
        width: screen.width,
        height: screen.height,
        rowBytes: screen.rowBytes,
      );
      expect(board.size, 8);
      expect(board.regions, kEightByEight);
      expect(board.top, 420);
      expect(board.left, 20);
      expect(board.bottom, 420 + 8 * 80 + 7 * 6 - 1);
      expect(
        board.regionColors.first,
        0xFF000000 | (72 << 16) | (138 << 8) | 88,
      );
    });

    test('玩到一半（滿版打叉、每行一隻貓）仍讀得出顏色', () {
      final FakeScreen screen = FakeScreen()..decorations();
      final List<List<List<int>>> corners = screen.board(kEightByEight);
      for (int r = 0; r < 8; r++) {
        for (int c = 0; c < 8; c++) {
          final List<int> xy = corners[r][c];
          if (c == (r * 3) % 8) {
            screen.cat(xy[0], xy[1], 80);
          } else {
            screen.cross(xy[0], xy[1], 80);
          }
        }
      }
      final MeowdokuBoard board = readMeowdokuBoard(
        screen.pixels,
        width: screen.width,
        height: screen.height,
        rowBytes: screen.rowBytes,
      );
      expect(board.regions, kEightByEight);
    });

    test('畫面上沒有盤面 → noGrid', () {
      final FakeScreen screen = FakeScreen()..decorations();
      expect(
        () => readMeowdokuBoard(
          screen.pixels,
          width: screen.width,
          height: screen.height,
          rowBytes: screen.rowBytes,
        ),
        throwsA(
          isA<MeowdokuReadException>().having(
            (MeowdokuReadException e) => e.failure,
            'failure',
            MeowdokuReadFailure.noGrid,
          ),
        ),
      );
    });

    test('兩個色塊同色 → regionMismatch，不會靜默併成一塊去解', () {
      final FakeScreen screen = FakeScreen();
      final List<List<int>> colors = List<List<int>>.of(kRegionRgb);
      colors[7] = colors[6];
      screen.board(kEightByEight, colors: colors);
      expect(
        () => readMeowdokuBoard(
          screen.pixels,
          width: screen.width,
          height: screen.height,
          rowBytes: screen.rowBytes,
        ),
        throwsA(
          isA<MeowdokuReadException>()
              .having((MeowdokuReadException e) => e.failure, 'failure',
                  MeowdokuReadFailure.regionMismatch)
              .having((MeowdokuReadException e) => e.found, 'found', 7)
              .having((MeowdokuReadException e) => e.expected, 'expected', 8),
        ),
      );
    });
  });
}
