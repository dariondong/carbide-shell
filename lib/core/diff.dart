/// 两份文本的差异，按 unified diff 输出。纯 Dart，不碰文件。
///
/// 只回答「这两个文件差在哪」：相同的部分压成上下文，只把变化的行写出来。
/// 两个 1 KB 的文件一样时返回空串，几乎不花代价。
library;

/// 一次对比的结果。
class DiffResult {
  const DiffResult({required this.text, this.added = 0, this.removed = 0});

  /// unified diff 全文。两个一样时是空串。
  final String text;

  final int added;
  final int removed;

  bool get same => text.isEmpty;
}

enum _Op { same, del, ins }

class _Line {
  const _Line(this.op, this.text);

  final _Op op;
  final String text;
}

/// 超过这个格子的矩阵就不做最长公共子序列，直接整段替换。
/// 2000 × 2000 会吃掉几十 MB，不值得为一份日志这么干。
const int _maxCells = 1000000;

/// 生成 unified diff。
///
/// [context] 是每个改动块前后各留几行上下文；0 就只写变化的行。
DiffResult unifiedDiff(
  String a,
  String b, {
  int context = 3,
  String aLabel = 'a',
  String bLabel = 'b',
}) {
  final List<String> left = _lines(a);
  final List<String> right = _lines(b);
  if (a == b) return const DiffResult(text: '');

  // 头尾相同的先切掉，真正要算的只有中间那一小段。
  int start = 0;
  while (start < left.length && start < right.length && left[start] == right[start]) {
    start += 1;
  }
  int endLeft = left.length;
  int endRight = right.length;
  while (endLeft > start && endRight > start && left[endLeft - 1] == right[endRight - 1]) {
    endLeft -= 1;
    endRight -= 1;
  }

  final List<String> middleLeft = left.sublist(start, endLeft);
  final List<String> middleRight = right.sublist(start, endRight);
  final List<_Line> ops = _opsFor(middleLeft, middleRight);
  final List<_Line> all = <_Line>[
    for (final String line in left.sublist(0, start)) _Line(_Op.same, line),
    ...ops,
    for (final String line in left.sublist(endLeft)) _Line(_Op.same, line),
  ];

  final String diff = _render(all, context: context, aLabel: aLabel, bLabel: bLabel);
  int added = 0;
  int removed = 0;
  for (final _Line line in ops) {
    if (line.op == _Op.ins) added += 1;
    if (line.op == _Op.del) removed += 1;
  }
  return DiffResult(text: diff, added: added, removed: removed);
}

List<String> _lines(String text) {
  if (text.isEmpty) return const <String>[];
  final List<String> out = text.replaceAll('\r\n', '\n').split('\n');
  // 文件末尾那个换行不算多出来的一行。
  if (out.isNotEmpty && out.last.isEmpty) out.removeLast();
  return out;
}

/// 中间那一段的最长公共子序列，返回到逐行的增删序列。
List<_Line> _opsFor(List<String> a, List<String> b) {
  if (a.isEmpty) return <_Line>[for (final String s in b) _Line(_Op.ins, s)];
  if (b.isEmpty) return <_Line>[for (final String s in a) _Line(_Op.del, s)];
  if (a.length * b.length > _maxCells) {
    return <_Line>[
      for (final String s in a) _Line(_Op.del, s),
      for (final String s in b) _Line(_Op.ins, s),
    ];
  }
  final int n = a.length;
  final int m = b.length;
  final List<List<int>> table =
      List<List<int>>.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (int i = n - 1; i >= 0; i -= 1) {
    for (int j = m - 1; j >= 0; j -= 1) {
      table[i][j] = a[i] == b[j]
          ? table[i + 1][j + 1] + 1
          : (table[i + 1][j] >= table[i][j + 1] ? table[i + 1][j] : table[i][j + 1]);
    }
  }
  final List<_Line> out = <_Line>[];
  int i = 0;
  int j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      out.add(_Line(_Op.same, a[i]));
      i += 1;
      j += 1;
      continue;
    }
    if (table[i + 1][j] >= table[i][j + 1]) {
      out.add(_Line(_Op.del, a[i]));
      i += 1;
    } else {
      out.add(_Line(_Op.ins, b[j]));
      j += 1;
    }
  }
  while (i < n) {
    out.add(_Line(_Op.del, a[i]));
    i += 1;
  }
  while (j < m) {
    out.add(_Line(_Op.ins, b[j]));
    j += 1;
  }
  return out;
}

/// 把逐行序列切成块，每块前后各留 [context] 行。
String _render(
  List<_Line> lines, {
  required int context,
  required String aLabel,
  required String bLabel,
}) {
  final int pad = context < 0 ? 0 : context;
  final List<int> changed = <int>[];
  for (int i = 0; i < lines.length; i += 1) {
    if (lines[i].op != _Op.same) changed.add(i);
  }
  if (changed.isEmpty) return '';

  // 改动挨得近就并成一块：相距不超过两倍上下文。
  final List<List<int>> blocks = <List<int>>[];
  for (final int index in changed) {
    if (blocks.isNotEmpty && index - blocks.last.last <= pad * 2 + 1) {
      blocks.last.add(index);
    } else {
      blocks.add(<int>[index]);
    }
  }

  final StringBuffer out = StringBuffer()
    ..write('--- $aLabel\n')
    ..write('+++ $bLabel\n');
  // 行号在原始文件里的位置：读到哪一行了。
  int aLine = 1;
  int bLine = 1;
  int cursor = 0;
  for (final List<int> block in blocks) {
    final int from = block.first - pad < cursor ? cursor : block.first - pad;
    final int to = block.last + pad >= lines.length ? lines.length - 1 : block.last + pad;
    // 走到起点之前，把跳过的相同行同时推进行号。
    for (int i = cursor; i < from; i += 1) {
      if (lines[i].op != _Op.ins) aLine += 1;
      if (lines[i].op != _Op.del) bLine += 1;
    }
    int aCount = 0;
    int bCount = 0;
    for (int i = from; i <= to; i += 1) {
      if (lines[i].op != _Op.ins) aCount += 1;
      if (lines[i].op != _Op.del) bCount += 1;
    }
    out
      ..write('@@ -${aCount == 0 ? aLine - 1 : aLine},$aCount '
          '+${bCount == 0 ? bLine - 1 : bLine},$bCount @@\n');
    for (int i = from; i <= to; i += 1) {
      final _Line line = lines[i];
      final String mark = switch (line.op) {
        _Op.del => '-',
        _Op.ins => '+',
        _Op.same => ' ',
      };
      out.write('$mark${line.text}\n');
      if (line.op != _Op.ins) aLine += 1;
      if (line.op != _Op.del) bLine += 1;
    }
    cursor = to + 1;
  }
  return out.toString();
}
