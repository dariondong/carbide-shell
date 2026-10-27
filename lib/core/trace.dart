/// 会话日志读成一条条轨迹。
///
/// 一个对话一份 `*.journal.jsonl`，一行一个 JSON：提问、模型请求、工具调用、
/// 工具回来的结果、收尾。这里只负责把那些行摊成一条时间线，纯 Dart，好单独测。
library;

import 'dart:convert';

/// 时间线上这一条是什么。
enum TraceKind { turn, llm, tool, note }

class TraceEntry {
  TraceEntry(this.kind, this.at);

  final TraceKind kind;

  /// 本地时间。
  final DateTime at;

  /// 第几轮、模型第几步。
  int turn = 0;
  int step = 0;

  /// 提问的原文，或者收尾那句话。
  String text = '';

  /// 工具名、审批卡上那句摘要、参数、策略怎么判的。
  String name = '';
  String summary = '';
  Map<String, Object?> args = const <String, Object?>{};
  String verdict = '';

  /// 跑成没跑成、用了多久、回来什么。
  bool hasResult = false;
  bool ok = false;
  int ms = 0;
  String output = '';

  /// 这一步的 token：进去的、其中命中缓存的、回来的。
  int prompt = 0;
  int cached = 0;
  int out = 0;

  bool get isTool => kind == TraceKind.tool;

  int get total => prompt + out;

  /// 审批卡那句话；没问过就是 allow。
  String get verdictText => switch (verdict) {
        'deny' => '被危险规则拦下',
        'ask' => '问过你才跑',
        _ => '',
      };

  /// 参数里最像「这一下在干什么」的那一项。
  String get argText {
    for (final String key in <String>['command', 'path', 'url', 'title', 'op', 'note']) {
      final Object? raw = args[key];
      if (raw == null) continue;
      final String value = '$raw'.trim();
      if (value.isNotEmpty) return value.replaceAll('\n', ' ');
    }
    return summary;
  }
}

/// 把一整份日志摊开。读不懂的行跳过，配不上结果的工具就还没有结果。
List<TraceEntry> parseJournal(String raw) {
  final List<TraceEntry> out = <TraceEntry>[];
  final Map<String, List<TraceEntry>> pending = <String, List<TraceEntry>>{};
  int turn = 0;
  for (final String line in raw.split('\n')) {
    final String text = line.trim();
    if (text.isEmpty) continue;
    Map<String, Object?> json;
    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is! Map) continue;
      json = Map<String, Object?>.from(decoded);
    } catch (_) {
      continue;
    }
    final DateTime at =
        DateTime.tryParse('${json['at'] ?? ''}')?.toLocal() ?? DateTime.now();
    switch ('${json['event'] ?? ''}') {
      case 'user':
        turn += 1;
        out.add(TraceEntry(TraceKind.turn, at)
          ..turn = turn
          ..text = '${json['text'] ?? ''}');
      case 'llm':
        out.add(TraceEntry(TraceKind.llm, at)
          ..turn = turn
          ..step = _int(json['step'])
          ..prompt = _int(json['prompt'])
          ..cached = _int(json['cached'])
          ..out = _int(json['out']));
      case 'tool':
        final TraceEntry call = TraceEntry(TraceKind.tool, at)
          ..turn = turn
          ..name = '${json['name'] ?? ''}'
          ..summary = '${json['summary'] ?? ''}'
          ..verdict = '${json['verdict'] ?? ''}';
        final Object? args = json['args'];
        if (args is Map) call.args = Map<String, Object?>.from(args);
        out.add(call);
        pending.putIfAbsent(call.name, () => <TraceEntry>[]).add(call);
      case 'result':
        final String name = '${json['name'] ?? ''}';
        final List<TraceEntry>? queue = pending[name];
        final TraceEntry? target =
            (queue == null || queue.isEmpty) ? null : queue.removeAt(0);
        final TraceEntry back = target ?? (TraceEntry(TraceKind.tool, at)..name = name);
        back
          ..hasResult = true
          ..ok = json['ok'] != false
          ..ms = _int(json['ms'])
          ..output = '${json['text'] ?? ''}';
        if (target == null) out.add(back);
      case 'final':
      case 'stop':
        out.add(TraceEntry(TraceKind.note, at)..text = '${json['text'] ?? ''}');
    }
  }
  return out;
}

int _int(Object? raw) {
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw) ?? 0;
  return 0;
}
