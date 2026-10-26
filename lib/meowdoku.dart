/// MeowDoku（貓咪在哪裡）的盤面辨識與解題。
///
/// 規則：N×N 的格子被分成 N 個色塊，每行、每列、每個色塊各放一隻貓，且任兩隻貓不能
/// 相鄰——**含斜角**。只看上下左右的話，「每行每列各一隻」本身就保證了不會相鄰，
/// 那條規則就沒有意義了，所以一定是八方向。
///
/// 這是約束滿足問題，沒有封閉公式，但盤面小、限制強，逐行回溯在毫秒內就解完。
///
/// 純 Dart、不碰 Flutter，方便直接拿像素陣列寫測試。
library;

import 'dart:typed_data';

/// 一張辨識出來的盤面。座標都是截圖的實體像素。
class MeowdokuBoard {
  const MeowdokuBoard({
    required this.regions,
    required this.regionColors,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.rowCenters,
    required this.colCenters,
    required this.cats,
  });

  /// `regions[row][col]` 是那一格所屬的色塊編號（0 起算）。
  final List<List<int>> regions;

  /// 色塊編號 → 取樣到的顏色（0xAARRGGBB），畫小圖時沿用遊戲本身的配色。
  final List<int> regionColors;

  final int left;
  final int top;
  final int right;
  final int bottom;

  /// 每一行／每一列格子的中心。取自投影量到的實際位置，不用邊界等分推算：間隔與格子
  /// 寬度都是整數像素，等分的捨入誤差會一路累積到最後一格。
  final List<int> rowCenters;
  final List<int> colCenters;

  /// `cats[row][col]`：截圖當下那一格有沒有放貓（使用者放的、或關卡送的）。
  final List<List<bool>> cats;

  int get size => regions.length;
}

enum MeowdokuReadFailure {
  /// 找不到一排排等寬、等距的色塊。
  noGrid,

  /// 找到的行數與列數不一樣。
  gridMismatch,

  /// 顏色種類數跟盤面邊長對不上（色差太小被併掉，或格子上有東西蓋住取樣點）。
  regionMismatch,
}

class MeowdokuReadException implements Exception {
  const MeowdokuReadException(this.failure, {this.found, this.expected});

  final MeowdokuReadFailure failure;
  final int? found;
  final int? expected;

  @override
  String toString() => 'MeowdokuReadException($failure, found: $found, '
      'expected: $expected)';
}

/// 從 RGBA 截圖裡找出盤面並讀出色塊。
///
/// 做法是投影：盤面上一整列的格子幾乎鋪滿寬度，而格子之間的間隔是白的，所以「每一列
/// 有幾個有色像素」畫成曲線，盤面會是 N 段等高、等距的高原。標題、規則卡片、底部按鈕
/// 也有顏色，但湊不出一串等距的高原，靠「最長的一串」就能把它們排除。
///
/// 失敗時丟 [MeowdokuReadException]。
MeowdokuBoard readMeowdokuBoard(
  Uint8List rgba, {
  required int width,
  required int height,
  required int rowBytes,
}) {
  bool colored(int x, int y) {
    final int i = y * rowBytes + x * 4;
    final int r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    // 遊戲的頁面底色（約 246,242,239）與盤面間隔（純白）都算「白」；最淺的格子色
    // （淡黃約 245,218,143）最小通道仍在 150 上下，門檻放 235 兩邊都有餘裕。
    return r <= _kWhiteMin || g <= _kWhiteMin || b <= _kWhiteMin;
  }

  // 每隔一個像素取樣就夠了：格子與間隔都有好幾個像素寬，全取只是多跑四倍。
  final List<int> rowProfile = List<int>.generate(height, (int y) {
    int n = 0;
    for (int x = 0; x < width; x += 2) {
      if (colored(x, y)) n++;
    }
    return n;
  });
  final List<_Span>? rows = _longestEvenChain(rowProfile);
  // 遊戲最大 12×12（玩家觀察）。更大的「盤面」是別的 UI 湊出來的，而且解題時間隨 N
  // 暴增（review 在桌機 JIT 量到刻意無解的 13×13 要 14 秒），解題期間懸浮層是吃掉
  // 點擊的透明全螢幕。
  if (rows == null || rows.length > kMeowdokuMaxSize) {
    throw const MeowdokuReadException(MeowdokuReadFailure.noGrid);
  }
  final int top = rows.first.start;
  final int bottom = rows.last.end;

  // 欄的投影只看盤面那段高度，否則上下的 UI 會把間隔那幾欄也染成有色。
  final List<int> colProfile = List<int>.generate(width, (int x) {
    int n = 0;
    for (int y = top; y <= bottom; y += 2) {
      if (colored(x, y)) n++;
    }
    return n;
  });
  final List<_Span>? cols = _longestEvenChain(colProfile);
  if (cols == null) {
    throw const MeowdokuReadException(MeowdokuReadFailure.noGrid);
  }
  if (cols.length != rows.length) {
    throw MeowdokuReadException(
      MeowdokuReadFailure.gridMismatch,
      found: cols.length,
      expected: rows.length,
    );
  }

  final int n = rows.length;
  final List<int> palette = <int>[];
  final List<List<int>> regions = <List<int>>[];
  for (final _Span r in rows) {
    final List<int> line = <int>[];
    for (final _Span c in cols) {
      final int color = _sampleCell(rgba, rowBytes, c, r);
      int index = palette.indexWhere(
        (int p) => _distance(p, color) <= _kSameColorTolerance,
      );
      if (index < 0) {
        palette.add(color);
        index = palette.length - 1;
      }
      line.add(index);
    }
    regions.add(line);
  }
  if (palette.length != n) {
    throw MeowdokuReadException(
      MeowdokuReadFailure.regionMismatch,
      found: palette.length,
      expected: n,
    );
  }
  return MeowdokuBoard(
    regions: regions,
    regionColors: palette,
    left: cols.first.start,
    top: top,
    right: cols.last.end,
    bottom: bottom,
    rowCenters: <int>[for (final _Span r in rows) (r.start + r.end) ~/ 2],
    colCenters: <int>[for (final _Span c in cols) (c.start + c.end) ~/ 2],
    cats: <List<bool>>[
      for (final _Span r in rows)
        <bool>[for (final _Span c in cols) _hasCat(rgba, rowBytes, c, r)],
    ],
  );
}

/// 照解答把盤面填完要連點兩下的格子，依行由上而下。
///
/// 遊戲的操作：點一下打叉、再點一下拿掉，**連點兩下**放貓——空格與打了叉的格子都是
/// 連點兩下就變成貓（實機第 2350 關驗過），所以只要跳過已經是貓的格子。解答以外的
/// 格子不動：叉留著無害。
///
/// 解答以外的格子上有貓時丟 [MeowdokuWrongCatException]：留著它盤面永遠填不完，而
/// 點貓會變成什麼沒確認過，不替使用者拿掉。
List<({int row, int col})> planMeowdokuFill(
  List<List<bool>> cats,
  List<int> solution,
) {
  for (int r = 0; r < cats.length; r++) {
    for (int c = 0; c < cats[r].length; c++) {
      if (cats[r][c] && solution[r] != c) {
        throw MeowdokuWrongCatException(r, c);
      }
    }
  }
  return <({int row, int col})>[
    for (int r = 0; r < solution.length; r++)
      if (!cats[r][solution[r]]) (row: r, col: solution[r]),
  ];
}

class MeowdokuWrongCatException implements Exception {
  const MeowdokuWrongCatException(this.row, this.col);

  final int row;
  final int col;

  @override
  String toString() => 'MeowdokuWrongCatException($row, $col)';
}

/// 解題。最多找 [limit] 組解就停；每組是「每一行的貓放在第幾列」。
///
/// 預設找到第二組就停，呼叫端要把「不只一組」當成**讀錯**：關卡都是唯一解，而某一格
/// 被歸到隔壁色塊時，顏色種類數仍然是 N、[readMeowdokuBoard] 的檢查擋不到。實測第 10
/// 關把任一格換成相鄰色塊的 162 種讀法中，42 種會解出錯答案，而這 42 種全都不只一組
/// 解——只取第一組的話，使用者會拿到一個看起來很有把握的錯答案。
List<List<int>> solveMeowdoku(List<List<int>> regions, {int limit = 2}) {
  final int n = regions.length;
  final List<int> placed = List<int>.filled(n, -1);
  final List<List<int>> solutions = <List<int>>[];
  // 位元集合：n 最多十幾，int 裝得下，比 Set 快也省配置。
  void place(int row, int usedCols, int usedRegions) {
    if (row == n) {
      solutions.add(List<int>.of(placed));
      return;
    }
    for (int col = 0; col < n && solutions.length < limit; col++) {
      if (usedCols & (1 << col) != 0) continue;
      final int region = regions[row][col];
      if (usedRegions & (1 << region) != 0) continue;
      // 每行只有一隻，所以「不相鄰」只需要跟上一行比：同列已被 usedCols 擋掉，剩斜角。
      if (row > 0 && (placed[row - 1] - col).abs() <= 1) continue;
      placed[row] = col;
      place(row + 1, usedCols | (1 << col), usedRegions | (1 << region));
    }
  }

  place(0, 0, 0);
  return solutions;
}

const int kMeowdokuMaxSize = 12;

const int _kWhiteMin = 235;

/// 貓毛的黑。最深的格子色（深綠約 72,138,88）至少有一個通道遠高於此。
const int _kBlackMax = 70;

/// 兩個格子色要差多少才算不同色塊（RGB 三通道差的絕對值總和）。
///
/// 實測第 10 關最接近的兩色（深藍 88,117,161 與青藍 90,167,189）差 80；同一個色塊內
/// 各格取樣的差異是個位數。放在中間偏低，寧可多分出一色（會報 regionMismatch、
/// 看得出哪裡錯），也不要把兩個色塊併成一個（會解出錯的答案）。
const int _kSameColorTolerance = 36;

class _Span {
  const _Span(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start + 1;
}

/// 投影曲線裡「最長的一串等寬、等距高原」。少於 4 段就當作沒找到——不會有那麼小的
/// 盤面，而 2、3 段很容易被其他 UI 湊出來。
List<_Span>? _longestEvenChain(List<int> profile) {
  int peak = 0;
  for (final int v in profile) {
    if (v > peak) peak = v;
  }
  if (peak == 0) return null;
  // 相對門檻而不是固定比例：盤面不一定鋪滿寬度。門檻壓低是因為玩到一半時整排都可能
  // 打了叉：穿過格子中段的那幾列，每格被兩條白線各吃掉一截（實機線寬約一成二，合計
  // 約三成半），門檻太高的話一格會斷成上下兩段高原。間隔那幾列幾乎是 0，壓低門檻
  // 不會把間隔誤認成格子。
  final int threshold = (peak * 0.35).ceil();
  final List<_Span> plateaus = <_Span>[];
  int? start;
  for (int i = 0; i <= profile.length; i++) {
    final bool high = i < profile.length && profile[i] >= threshold;
    if (high) {
      start ??= i;
    } else if (start != null) {
      // 一兩個像素的突起是文字筆畫或反鋸齒，不是格子。
      if (i - start >= 8) plateaus.add(_Span(start, i - 1));
      start = null;
    }
  }

  List<_Span>? best;
  for (int i = 0; i < plateaus.length; i++) {
    final List<_Span> chain = <_Span>[plateaus[i]];
    final int size = plateaus[i].length;
    for (int j = i + 1; j < plateaus.length; j++) {
      final _Span prev = chain.last;
      final _Span next = plateaus[j];
      final int gap = next.start - prev.end - 1;
      final bool sameSize = (next.length - size).abs() <= size * 0.2;
      // 間隔要有、但不能比半格還寬，否則就是跳到另一塊 UI 了。
      final bool tight = gap >= 1 && gap <= size * 0.5;
      if (!sameSize || !tight) break;
      chain.add(next);
    }
    if (chain.length >= 4 && (best == null || chain.length > best.length)) {
      best = chain;
    }
  }
  return best;
}

/// 取一格的顏色：沿著格子外圈取 8 點（四角 + 四邊中點），丟掉白色與黑色的點，
/// 剩下的取多數。
///
/// 玩到一半的盤面，格子上會蓋兩種東西（第 1642 關實機截圖）：
/// - 叉：白色粗線，從約兩成畫到八成，**端點的圓頭正好落在「四角往內一點」**——
///   只取四角的話，打了叉的格子四個點可能全中白線。
/// - 貓頭：黑白兩色，幾乎蓋滿中央，耳朵頂到上緣附近，但四角與下緣仍露出底色。
/// 兩者都是白／黑，格子底色都是中間調，所以先濾掉再投票；外圈 8 點裡總有幾點落在
/// 空隙上。內縮 9% 是為了避開格子的圓角（半徑約一成）。
int _sampleCell(Uint8List rgba, int rowBytes, _Span col, _Span row) {
  final int dx = (col.length * 0.09).round();
  final int dy = (row.length * 0.09).round();
  final int mx = (col.start + col.end) ~/ 2;
  final int my = (row.start + row.end) ~/ 2;
  final List<List<int>> points = <List<int>>[
    <int>[col.start + dx, row.start + dy],
    <int>[col.end - dx, row.start + dy],
    <int>[col.start + dx, row.end - dy],
    <int>[col.end - dx, row.end - dy],
    <int>[mx, row.start + dy],
    <int>[mx, row.end - dy],
    <int>[col.start + dx, my],
    <int>[col.end - dx, my],
  ];
  final List<int> samples = <int>[];
  for (final List<int> p in points) {
    final int i = p[1] * rowBytes + p[0] * 4;
    final int r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    final bool white = r > _kWhiteMin && g > _kWhiteMin && b > _kWhiteMin;
    final bool black = r < _kBlackMax && g < _kBlackMax && b < _kBlackMax;
    if (white || black) continue;
    samples.add(0xFF000000 | (r << 16) | (g << 8) | b);
  }
  // 8 點全被蓋住的機率極低；真的發生就回白色，讓它在色塊計數那關被抓出來
  // （多出一種顏色 → regionMismatch），而不是猜一個顏色硬解。
  if (samples.isEmpty) return 0xFFFFFFFF;
  int best = samples.first;
  int bestVotes = 0;
  for (final int s in samples) {
    final int votes = samples
        .where((int o) => _distance(o, s) <= _kSameColorTolerance)
        .length;
    if (votes > bestVotes) {
      best = s;
      bestVotes = votes;
    }
  }
  return best;
}

/// 這格有沒有貓（貓頭的樣子見 [_sampleCell]）。格子底色沒有黑（最深的深綠也有一個
/// 通道遠高於 [_kBlackMax]），叉是白的，所以中央區域黑色夠多就是貓毛。
bool _hasCat(Uint8List rgba, int rowBytes, _Span col, _Span row) {
  int black = 0;
  int total = 0;
  for (int y = row.start + (row.length * 0.2).round();
      y <= row.end - (row.length * 0.2).round();
      y += 2) {
    for (int x = col.start + (col.length * 0.2).round();
        x <= col.end - (col.length * 0.2).round();
        x += 2) {
      final int i = y * rowBytes + x * 4;
      if (rgba[i] < _kBlackMax &&
          rgba[i + 1] < _kBlackMax &&
          rgba[i + 2] < _kBlackMax) {
        black++;
      }
      total++;
    }
  }
  return black * 100 >= total * _kCatBlackPercent;
}

/// 中央六成見方裡黑色占多少百分比以上算貓。實機第 2350 關量到貓 40～41%，空格與
/// 打叉的格子都是 0%，取遠低於貓的值。
const int _kCatBlackPercent = 8;

int _distance(int a, int b) {
  int d = 0;
  for (int shift = 0; shift <= 16; shift += 8) {
    d += (((a >> shift) & 0xFF) - ((b >> shift) & 0xFF)).abs();
  }
  return d;
}
