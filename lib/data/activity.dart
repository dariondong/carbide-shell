import 'dart:async';

import 'foreground.dart';

/// 现在在忙什么。对话和定时任务都往这里报一句，前台通知只由这里写。
///
/// 一条通知装不下几件事：两件以上就写「2 个在忙」，后面跟最近动过的那一件。
/// 全都忙完了才收掉通知；人不在应用里时留一句结果。
class ActivityBoard {
  final Map<String, String> _items = <String, String>{};

  /// 最久没动过的排在前面，最后一个是刚动过的。
  final List<String> _order = <String>[];
  bool _up = false;
  String _lastDone = '';

  bool get any => _items.isNotEmpty;

  int get count => _items.length;

  String get text {
    if (_items.isEmpty) return '';
    final String latest = _items[_order.last] ?? '';
    if (_items.length == 1) return latest;
    return '${_items.length} 个在忙 · $latest';
  }

  /// 报一句自己在干什么。[key] 用 `c:<对话 id>` 或 `t:<任务 id>`。
  void note(String key, String label) {
    _items[key] = label;
    _order.remove(key);
    _order.add(key);
    _push();
  }

  /// 这件事做完了。全都没了就把通知收掉。
  void done(String key, {String summary = ''}) {
    if (summary.isNotEmpty) _lastDone = summary;
    if (_items.remove(key) == null) {
      _order.remove(key);
      return;
    }
    _order.remove(key);
    _push();
  }

  void _push() {
    if (_items.isEmpty) {
      if (!_up) return;
      _up = false;
      unawaited(ForegroundTask.visible
          ? ForegroundTask.end()
          : ForegroundTask.finish(_lastDone));
      return;
    }
    if (!_up) {
      _up = true;
      unawaited(ForegroundTask.begin(text));
      return;
    }
    unawaited(ForegroundTask.update(text));
  }
}
