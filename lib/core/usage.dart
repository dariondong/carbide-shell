/// 模型用量：每一轮花掉多少 token，按天、按模型合计出来。
///
/// 只记数字，不记对话内容。纯 Dart，能单独测。
library;

/// 一轮对话的一笔账。
class UsageEntry {
  UsageEntry({
    required this.at,
    required this.model,
    this.prompt = 0,
    this.completion = 0,
    this.cached = 0,
    this.conversationId = '',
  });

  final DateTime at;
  final String model;

  /// 输入 token。多步的轮次里是那几步加起来的。
  final int prompt;
  final int completion;

  /// 输入里由服务端缓存命中的那部分。
  final int cached;
  final String conversationId;

  int get total => prompt + completion;

  double get cacheRate => prompt <= 0 || cached <= 0 ? 0 : cached / prompt;

  String get day => usageDayKey(at);

  Map<String, Object?> toJson() => <String, Object?>{
        'at': at.toIso8601String(),
        'model': model,
        'prompt': prompt,
        'completion': completion,
        'cached': cached,
        if (conversationId.isNotEmpty) 'conversation': conversationId,
      };

  static UsageEntry fromJson(Map<String, Object?> json) => UsageEntry(
        at: DateTime.tryParse('${json['at'] ?? ''}') ?? DateTime.now(),
        model: '${json['model'] ?? ''}',
        prompt: _intOf(json['prompt']),
        completion: _intOf(json['completion']),
        cached: _intOf(json['cached']),
        conversationId: '${json['conversation'] ?? ''}',
      );

  static int _intOf(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('${raw ?? ''}') ?? 0;
  }
}

/// 加总。轮数是笔数，不是步数。
class UsageTotals {
  int turns = 0;
  int prompt = 0;
  int completion = 0;
  int cached = 0;

  int get total => prompt + completion;

  double get cacheRate => prompt <= 0 || cached <= 0 ? 0 : cached / prompt;

  void add(UsageEntry e) {
    turns += 1;
    prompt += e.prompt;
    completion += e.completion;
    cached += e.cached;
  }

  void addAll(Iterable<UsageEntry> entries) {
    for (final UsageEntry e in entries) {
      add(e);
    }
  }

  bool get isEmpty => turns == 0;
}

/// `2026-10-26`
String usageDayKey(DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${at.year}-${two(at.month)}-${two(at.day)}';
}

/// 今天的零点。
DateTime usageTodayStart([DateTime? now]) {
  final DateTime at = now ?? DateTime.now();
  return DateTime(at.year, at.month, at.day);
}

/// 从哪一刻起算。`days` 是 1 = 今天，7 = 含今天在内的七天。
DateTime usageFrom(int days, [DateTime? now]) =>
    usageTodayStart(now).subtract(Duration(days: days <= 1 ? 0 : days - 1));

/// 落在窗口里的那些。
List<UsageEntry> usageSince(List<UsageEntry> all, DateTime from) =>
    all.where((UsageEntry e) => !e.at.isBefore(from)).toList();

/// 按模型合计，花得多的排前面。
List<UsageModelRow> usageByModel(List<UsageEntry> entries) {
  final Map<String, UsageTotals> buckets = <String, UsageTotals>{};
  for (final UsageEntry e in entries) {
    final String key = e.model.trim().isEmpty ? '未命名模型' : e.model.trim();
    buckets.putIfAbsent(key, () => UsageTotals()).add(e);
  }
  final List<UsageModelRow> rows = buckets.entries
      .map((MapEntry<String, UsageTotals> e) => UsageModelRow(model: e.key, totals: e.value))
      .toList();
  rows.sort((UsageModelRow a, UsageModelRow b) => b.totals.total.compareTo(a.totals.total));
  return rows;
}

class UsageModelRow {
  UsageModelRow({required this.model, required this.totals});

  final String model;
  final UsageTotals totals;
}

/// 一天一格的柱图用的数据。
class UsageDayRow {
  UsageDayRow({required this.day, required this.totals});

  final String day;
  final UsageTotals totals;
}

/// 最近 `days` 天，从早到晚，缺的那天补零。
List<UsageDayRow> usageLastDays(List<UsageEntry> entries, int days, [DateTime? now]) {
  final DateTime today = usageTodayStart(now);
  final List<UsageDayRow> out = <UsageDayRow>[];
  for (int i = days - 1; i >= 0; i -= 1) {
    final DateTime day = today.subtract(Duration(days: i));
    final String key = usageDayKey(day);
    final UsageTotals totals = UsageTotals()
      ..addAll(entries.where((UsageEntry e) => e.day == key));
    out.add(UsageDayRow(day: key, totals: totals));
  }
  return out;
}

/// token 数写成能一眼看懂的：980 / 1.2k / 12.4k / 1.03m。
String usageText(int tokens) {
  if (tokens < 1000) return '$tokens';
  if (tokens < 10000) return '${(tokens / 1000).toStringAsFixed(1)}k';
  if (tokens < 1000000) return '${(tokens / 1000).round()}k';
  return '${(tokens / 1000000).toStringAsFixed(2)}m';
}

/// 命中率写成百分比，没报缓存就是 `—`。
String usageRate(double rate, {int cached = 0}) {
  if (rate <= 0 || cached <= 0) return '—';
  return '${(rate * 100).round()}%';
}
