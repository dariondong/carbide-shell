import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../core/diff.dart';
import '../core/models.dart';
import '../core/tools.dart';
import '../data/hosts.dart';
import '../data/snapshots.dart';
import '../data/temp_files.dart';
import 'ssh_tools.dart';

/// `remote_diff`：两份已经存在的文件差在哪。
///
/// 跟「把 A 改成 B」是两件事：那个回答改完前后差什么，这个只还原事实。
/// 只回变化行，不把整份文件搬进上下文。
class RemoteDiffTool extends Tool {
  RemoteDiffTool({
    required this.pool,
    required this.hosts,
    required this.files,
    SnapshotStore? snapshots,
  }) : snapshots = snapshots ?? SnapshotStore(files.root);

  final SshPool pool;
  final HostStore hosts;
  final TempFiles files;

  /// 每次比完留一份存样，「一天前」才有得比。
  final SnapshotStore snapshots;

  /// 一侧最多读这么多；再大就不是「比一下」，该换别的办法。
  static const int _maxBytes = 4 * 1024 * 1024;

  @override
  String get name => 'remote_diff';

  @override
  String get description =>
      '比两个已经在的文件差在哪，只回变化的行。同一台机上两个文件（.bak 与现行配置）、'
      '两台机各一份（看同一套配置有没有漂移）、或者跟之前存下的样比（路径后面加 @24h、@30m、@2d）。'
      '存样是每次比完自己留的，第一次跟 @24h 比会说还没有那么早的样。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'a': <String, Object?>{
            'type': 'string',
            'description': '这一侧的文件路径，可以带 @24h / @30m / @2d 表示跟那时存的样比',
          },
          'b': <String, Object?>{
            'type': 'string',
            'description': '另一侧，写法同上',
          },
          'host_a': <String, Object?>{'type': 'string', 'description': 'a 在哪台主机上'},
          'host_b': <String, Object?>{
            'type': 'string',
            'description': 'b 在哪台主机上，留空就跟 host_a 一样',
          },
          'context': <String, Object?>{
            'type': 'integer',
            'description': '每个改动块前后各留几行，默认 3，写 0 就只回变化行',
          },
          'max_lines': <String, Object?>{
            'type': 'integer',
            'description': 'diff 最多回多少行，默认 400',
          },
        },
        'required': <String>['a', 'b'],
      };

  /// 只读。
  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.read;

  @override
  String summarize(Map<String, Object?> args) {
    final String a = readString(args, 'a');
    final String b = readString(args, 'b');
    return '比 ${a.isEmpty ? '?' : a} ↔ ${b.isEmpty ? '?' : b}';
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final _Side? a = _Side.parse(readString(args, 'a'));
    final _Side? b = _Side.parse(readString(args, 'b'));
    if (a == null || b == null) {
      return const ToolOutcome.failure('a 和 b 都要给文件路径。');
    }
    final String hostA = readString(args, 'host_a').trim();
    final String hostB = readString(args, 'host_b').trim();
    final HostEntry? entryA = _host(hostA.isNotEmpty ? hostA : hostB);
    final HostEntry? entryB = _host(hostB.isNotEmpty ? hostB : hostA);
    if (entryA == null || entryB == null) {
      return ToolOutcome.failure(
        hostA.isEmpty && hostB.isEmpty && hosts.hosts.length != 1
            ? '主机列表里不止一台，要说清 a 和 b 各在哪台上。'
            : '主机列表里没有这台。',
      );
    }

    final _Loaded left = await _load(entryA, a);
    if (left.error.isNotEmpty) return ToolOutcome.failure(left.error);
    final _Loaded right = await _load(entryB, b);
    if (right.error.isNotEmpty) return ToolOutcome.failure(right.error);

    final String labelA = '${entryA.name}:${a.path}${a.note}';
    final String labelB = '${entryB.name}:${b.path}${b.note}';
    final StringBuffer out = StringBuffer('$labelA ↔ $labelB\n');

    // 一侧要的那会儿还没有存样：说清楚，别假装比过。
    if (left.missing.isNotEmpty || right.missing.isNotEmpty) {
      for (final String line in <String>[...left.missing, ...right.missing]) {
        out.writeln(line);
      }
      return ToolOutcome.success(
        stdout: out.toString().trimRight(),
        meta: <String, Object?>{'same': false, 'no_snapshot': true},
      );
    }

    final int lines = _clamp(readInt(args, 'context', fallback: 3), 0, 20);
    final int maxLines = _clamp(readInt(args, 'max_lines', fallback: 400), 20, 4000);

    if (left.text == right.text) {
      out.write('一样：${_linesOf(left.text)} 行、${left.text.length} 字符。');
      return ToolOutcome.success(
        stdout: out.toString(),
        meta: <String, Object?>{'same': true, 'lines': _linesOf(left.text)},
      );
    }
    final DiffResult diff = unifiedDiff(
      left.text,
      right.text,
      context: lines,
      aLabel: labelA,
      bLabel: labelB,
    );
    if (diff.same) {
      out.write('一样：${_linesOf(left.text)} 行。');
      return ToolOutcome.success(
        stdout: out.toString(),
        meta: <String, Object?>{'same': true},
      );
    }
    final List<String> all = diff.text.split('\n');
    final bool cut = all.length > maxLines;
    out.write((cut ? all.take(maxLines).join('\n') : diff.text).trimRight());
    out.writeln();
    out.write('共 +${diff.added} −${diff.removed} 行');
    if (cut) out.write('，只回了前 $maxLines 行');
    out.write('。');
    return ToolOutcome.success(
      stdout: out.toString(),
      meta: <String, Object?>{
        'same': false,
        'added': diff.added,
        'removed': diff.removed,
        'truncated': cut,
      },
    );
  }

  HostEntry? _host(String name) {
    final String wanted = name.trim();
    if (wanted.isNotEmpty) return hosts.byName(wanted);
    if (hosts.hosts.length == 1) return hosts.hosts.first;
    return null;
  }

  /// 一侧的内容：现在读、或者从存样里取。
  Future<_Loaded> _load(HostEntry entry, _Side side) async {
    if (side.age == Duration.zero) {
      try {
        final String text = await _readRemote(entry, side.path);
        await snapshots.save(entry.name, side.path, text);
        return _Loaded(text: text);
      } catch (e) {
        return _Loaded(error: '${entry.name}:${side.path} 读不出来：$e');
      }
    }
    final Snapshot? older = await snapshots.older(entry.name, side.path, side.age);
    if (older != null) return _Loaded(text: older.text, note: '${side.ageText}前');
    // 还没有那么早的样：现在这份先存下，下次再比。
    try {
      final String text = await _readRemote(entry, side.path);
      final Snapshot saved = await snapshots.save(entry.name, side.path, text);
      return _Loaded(
        text: text,
        note: '${side.ageText}前',
        missing: <String>[
          '${entry.name}:${side.path} 还没有 ${side.ageText}前的存样。',
          '现在这份已经存下了（${_timeText(saved.at)}），下次再比就有得比。',
        ],
      );
    } catch (e) {
      return _Loaded(error: '${entry.name}:${side.path} 读不出来：$e');
    }
  }

  Future<String> _readRemote(HostEntry entry, String path) async {
    final SSHClient client = await pool.connect(entry);
    final SftpClient sftp = await client.sftp();
    final SftpFile file = await sftp.open(path);
    final BytesBuilder builder = BytesBuilder();
    int total = 0;
    await for (final Uint8List chunk in file.read()) {
      builder.add(chunk);
      total += chunk.length;
      if (total > _maxBytes) {
        await file.close();
        throw StateError('超过 ${_maxBytes ~/ (1024 * 1024)} MB');
      }
    }
    await file.close();
    return utf8.decode(builder.takeBytes(), allowMalformed: true);
  }
}

/// 一侧的写法：路径，可能后面挂着 `@24h`。
class _Side {
  const _Side({required this.path, required this.age, required this.ageText});

  final String path;
  final Duration age;

  /// `24 小时` 这样的原文，用来写在标题和话里。
  final String ageText;

  static _Side? parse(String raw) {
    final String text = raw.trim();
    if (text.isEmpty) return null;
    final RegExpMatch? m = RegExp(r'^(.*?)@(\d+)([hdm])$').firstMatch(text);
    if (m == null) return _Side(path: text, age: Duration.zero, ageText: '');
    final int n = int.tryParse(m.group(2) ?? '') ?? 0;
    final String unit = m.group(3) ?? 'h';
    final String path = (m.group(1) ?? '').trim();
    if (path.isEmpty || n <= 0) {
      return _Side(path: text, age: Duration.zero, ageText: '');
    }
    final Duration age = unit == 'd'
        ? Duration(days: n)
        : unit == 'm'
            ? Duration(minutes: n)
            : Duration(hours: n);
    final String label = unit == 'd'
        ? '$n 天'
        : unit == 'm'
            ? '$n 分钟'
            : '$n 小时';
    return _Side(path: path, age: age, ageText: label);
  }

  /// 标题里带上「跟什么时候比」，别让人以为两边都是现在。
  String get note => age == Duration.zero ? '' : '[$ageText前]';
}

class _Loaded {
  _Loaded({
    this.text = '',
    this.error = '',
    this.note = '',
    this.missing = const <String>[],
  });

  final String text;
  final String error;

  /// 这份是从存样里取出来的，比如 `24 小时前`。
  final String note;

  /// 要跟着标题一起说清楚的话：想要的存样还没有。
  final List<String> missing;
}

int _clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

int _linesOf(String text) {
  if (text.trim().isEmpty) return 0;
  return text.replaceAll('\r\n', '\n').split('\n').length;
}

String _timeText(DateTime t) {
  String two(int v) => v < 10 ? '0$v' : '$v';
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
