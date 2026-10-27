import 'dart:convert';
import 'dart:io';

/// 一份存样：某个时刻某个主机上某个文件的内容。
class Snapshot {
  const Snapshot({required this.at, required this.text});

  final DateTime at;
  final String text;
}

/// 存样：比完一次就把「现在这份」按时间存下来，下次要跟「一天前」比才有得比。
///
/// 只是文件，放在临时文件区下面的 `snapshots/`。每个文件只留最近 [keep] 份，
/// 不然一份天天变的配置几个月就把临时区撑满了。
class SnapshotStore {
  SnapshotStore(this.root);

  /// 临时文件区的根目录。
  final Directory root;

  /// 同一份文件留几份。
  static const int keep = 12;

  Directory get dir => Directory('${root.path}/snapshots');

  /// 主机 + 路径 → 一个短名字，避免路径里的斜杠和空格进文件名。
  String key(String host, String path) {
    final String raw = '${host.trim()}|${path.trim()}';
    int hash = 0x811c9dc5;
    for (final int c in utf8.encode(raw)) {
      hash ^= c;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// 存一份。[at] 只给测试用。
  Future<Snapshot> save(String host, String path, String text, {DateTime? at}) async {
    final DateTime when = at ?? DateTime.now();
    dir.createSync(recursive: true);
    final String k = key(host, path);
    final File file = File('${dir.path}/$k-${when.millisecondsSinceEpoch}.txt');
    await file.writeAsString(text, flush: true);
    await _prune(k);
    return Snapshot(at: when, text: text);
  }

  /// 这个文件存过哪些份，新的在前。
  List<Snapshot> list(String host, String path) {
    if (!dir.existsSync()) return const <Snapshot>[];
    final String k = key(host, path);
    final List<File> mine = dir
        .listSync()
        .whereType<File>()
        .where((File f) => f.path.split(Platform.pathSeparator).last.startsWith('$k-'))
        .toList();
    final List<Snapshot> out = <Snapshot>[];
    for (final File f in mine) {
      final String name = f.path.split(Platform.pathSeparator).last;
      final int? stamp = int.tryParse(
        name.replaceFirst('$k-', '').replaceFirst(RegExp(r'\.txt$'), ''),
      );
      if (stamp == null) continue;
      try {
        out.add(Snapshot(
          at: DateTime.fromMillisecondsSinceEpoch(stamp),
          text: f.readAsStringSync(),
        ));
      } catch (_) {
        // 读不出来的那份当没存过。
      }
    }
    out.sort((Snapshot a, Snapshot b) => b.at.compareTo(a.at));
    return out;
  }

  /// 找一份至少 [age] 那么早的存样：挑满足条件里最新的那份。
  Future<Snapshot?> older(String host, String path, Duration age, {DateTime? now}) async {
    final DateTime limit = (now ?? DateTime.now()).subtract(age);
    for (final Snapshot s in list(host, path)) {
      if (!s.at.isAfter(limit)) return s;
    }
    return null;
  }

  Future<void> _prune(String k) async {
    final List<File> mine = dir
        .listSync()
        .whereType<File>()
        .where((File f) => f.path.split(Platform.pathSeparator).last.startsWith('$k-'))
        .toList()
      ..sort((File a, File b) => a.path.compareTo(b.path));
    while (mine.length > keep) {
      try {
        mine.removeAt(0).deleteSync();
      } catch (_) {
        return;
      }
    }
  }
}
