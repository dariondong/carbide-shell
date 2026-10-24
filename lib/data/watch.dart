import 'dart:convert';
import 'dart:io';

import '../core/watch.dart';

/// 资源监听的清单，和主机、设置、定时任务并排放在应用数据目录里。
class WatchStore {
  WatchStore(this.file);

  final File file;
  final List<WatchTask> _items = <WatchTask>[];

  List<WatchTask> get all => List<WatchTask>.unmodifiable(_items);

  WatchTask? byId(String id) {
    for (final WatchTask w in _items) {
      if (w.id == id) return w;
    }
    return null;
  }

  Future<void> load() async {
    _items.clear();
    if (!file.existsSync()) return;
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        final Object? list = decoded['watches'];
        if (list is List) {
          for (final Object? raw in list) {
            if (raw is! Map) continue;
            final WatchTask w = WatchTask.fromJson(Map<String, Object?>.from(raw));
            if (w.id.isEmpty || w.hostId.isEmpty) continue;
            _items.add(w);
          }
        }
      }
    } catch (_) {
      // 文件坏了就从空清单开始。
    }
  }

  Future<void> save() async {
    file.parent.createSync(recursive: true);
    final String text = const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'watches': _items.map((WatchTask w) => w.toJson()).toList(),
    });
    await file.writeAsString(text);
  }

  Future<void> upsert(WatchTask task) async {
    final int index = _items.indexWhere((WatchTask w) => w.id == task.id);
    if (index >= 0) {
      _items[index] = task;
    } else {
      _items.add(task);
    }
    await save();
  }

  Future<void> remove(String id) async {
    _items.removeWhere((WatchTask w) => w.id == id);
    await save();
  }

  static String newId() => 'w${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
}
