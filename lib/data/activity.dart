import 'dart:async';

import 'foreground.dart';

/// 现在在忙什么。对话和定时任务都往这里报一句，前台通知只由这里写。
///
/// 一条通知装不下几件事：两件以上就写「2 个在忙」，后面跟最近动过的那一件。
/// 全都忙完了才收掉通知；人不在应用里时留一句结果。
class ActivityBoard {
  ActivityBoard({this.styleOf});

  /// 通知长什么样：每次重画都问一遍设置里的那一项。
  final String Function()? styleOf;

  final Map<String, String> _items = <String, String>{};

  /// 最久没动过的排在前面，最后一个是刚动过的。
  final List<String> _order = <String>[];

  /// 最近说过的几句，新的在后。大文本和会话样式拿它铺开。
  final List<String> _lines = <String>[];

  /// 最近说话的是哪个对话。在通知里回的那句话就发给它。
  String lastConversationId = '';

  bool _up = false;
  String _lastDone = '';

  static const int _keepLines = 4;

  String get notifStyle => styleOf?.call() ?? 'simple';

  /// 最近的几句，新的在前。
  List<String> get recent => List<String>.unmodifiable(_lines.reversed);

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
    remember(key);
    _remember(label);
    _push();
  }

  /// 这件事做完了。全都没了就把通知收掉。
  void done(String key, {String summary = ''}) {
    if (summary.isNotEmpty) _lastDone = summary;
    remember(key);
    if (_items.remove(key) == null) {
      _order.remove(key);
      return;
    }
    _order.remove(key);
    _push();
  }

  /// 记住最近动过的那个对话，通知里回的话才有地方可去。
  void remember(String key) {
    if (!key.startsWith('c:')) return;
    final String id = key.substring(2);
    if (id.isNotEmpty) lastConversationId = id;
  }

  void _remember(String label) {
    final String text = label.trim();
    if (text.isEmpty) return;
    if (_lines.isNotEmpty && _lines.last == text) return;
    _lines.add(text);
    while (_lines.length > _keepLines) {
      _lines.removeAt(0);
    }
  }

  void _push() {
    if (_items.isEmpty) {
      if (!_up) return;
      _up = false;
      unawaited(ForegroundTask.visible
          ? ForegroundTask.end()
          : ForegroundTask.finish(_lastDone, style: notifStyle, lines: recent));
      return;
    }
    final String text = this.text;
    if (!_up) {
      _up = true;
      unawaited(ForegroundTask.begin(text, style: notifStyle, lines: recent));
      return;
    }
    unawaited(ForegroundTask.update(text, lines: recent));
  }
}
