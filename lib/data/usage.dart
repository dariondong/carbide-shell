import 'dart:convert';
import 'dart:io';

import '../core/usage.dart';

/// 用量账本：一轮对话结束记一笔，越老越先丢。
class UsageStore {
  UsageStore(this.file);

  final File file;
  final List<UsageEntry> _items = <UsageEntry>[];
  bool _loaded = false;

  /// 最多留这么多笔。一轮一笔，用一年也到不了。
  static const int maxEntries = 20000;

  /// 超过这么多天的先不看。
  static const int keepDays = 400;

  List<UsageEntry> get all => List<UsageEntry>.unmodifiable(_items);

  bool get isLoaded => _loaded;

  Future<void> load() async {
    _items.clear();
    _loaded = true;
    if (!file.existsSync()) return;
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        final Object? list = decoded['usage'];
        if (list is List) {
          for (final Object? raw in list) {
            if (raw is! Map) continue;
            _items.add(UsageEntry.fromJson(Map<String, Object?>.from(raw)));
          }
        }
      }
    } catch (_) {
      // 账本坏了不挡住应用，从空账本开始。
    }
    _items.sort((UsageEntry a, UsageEntry b) => a.at.compareTo(b.at));
  }

  /// 记一笔。只有真花了 token 才记。
  Future<void> record(UsageEntry entry) async {
    if (entry.total <= 0) return;
    _items.add(entry);
    _prune();
    await save();
  }

  Future<void> clear() async {
    _items.clear();
    await save();
  }

  Future<void> save() async {
    file.parent.createSync(recursive: true);
    final String text = const JsonEncoder.withIndent(' ').convert(<String, Object?>{
      'usage': _items.map((UsageEntry e) => e.toJson()).toList(),
    });
    await file.writeAsString(text);
  }

  void _prune() {
    final DateTime cutoff = DateTime.now().subtract(const Duration(days: keepDays));
    _items.removeWhere((UsageEntry e) => e.at.isBefore(cutoff));
    if (_items.length > maxEntries) {
      _items.removeRange(0, _items.length - maxEntries);
    }
  }
}
