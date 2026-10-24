/// 定时任务的模型与时刻计算。
///
/// 纯 Dart：不 import Flutter，也不碰文件，排时刻这件事可以单独测。
/// 「下一次什么时候」只按本机本地时间算，跨时区不特殊照顾。
library;

/// 四种排法。日记时、按星期、按间隔、只跑一次。
enum ScheduleKind { daily, weekly, interval, once }

/// 一个任务最多留多少条运行记录，再老的挤掉。
const int kMaxRuns = 20;

/// 到点那一刻判断该做什么。
enum DueAction {
  /// 还没到点，或者任务停用了。
  none,

  /// 到点不久，现在就跑。
  run,

  /// 已经过了一阵（应用被清掉、手机睡着），补跑一次。
  runLate,

  /// 错过太久，这一次不补，直接排下一次。
  skip,
}

const List<String> kWeekNames = <String>['一', '二', '三', '四', '五', '六', '日'];

String _two(int n) => n.toString().padLeft(2, '0');

/// 一天里的第几分钟写成 `03:00`。
String clockText(int minuteOfDay) {
  final int m = minuteOfDay < 0 ? 0 : (minuteOfDay > 1439 ? 1439 : minuteOfDay);
  return '${_two(m ~/ 60)}:${_two(m % 60)}';
}

/// `10-24 03:00`。年份不同才带上年份。
String stampText(DateTime at, {DateTime? now}) {
  final DateTime ref = now ?? DateTime.now();
  final String md = '${_two(at.month)}-${_two(at.day)} ${_two(at.hour)}:${_two(at.minute)}';
  return at.year == ref.year ? md : '${at.year}-$md';
}

/// 「还有 3 分钟」「已过 2 小时」。null 给空串。
String untilText(DateTime? at, DateTime now) {
  if (at == null) return '';
  final Duration d = at.difference(now);
  final bool future = !d.isNegative;
  final Duration abs = d.abs();
  final String span;
  if (abs.inMinutes < 1) {
    span = '不到 1 分钟';
  } else if (abs.inMinutes < 60) {
    span = '${abs.inMinutes} 分钟';
  } else if (abs.inHours < 24) {
    final int m = abs.inMinutes % 60;
    span = m == 0 ? '${abs.inHours} 小时' : '${abs.inHours} 小时 $m 分';
  } else {
    final int h = abs.inHours % 24;
    span = h == 0 ? '${abs.inDays} 天' : '${abs.inDays} 天 $h 小时';
  }
  return future ? '还有 $span' : '已过 $span';
}

/// 一次运行的结果。完整回答留一份，过期的那张纸不必再翻。
class TaskRun {
  TaskRun({
    required this.at,
    this.ok = false,
    this.note = '',
    this.answer = '',
    this.steps = 0,
    this.tokens = 0,
    this.late = false,
    this.missed = false,
  });

  /// 原定的时刻。错过的那一条记的是原定时刻，不是发现它的时刻。
  final DateTime at;
  final bool ok;

  /// 一句话结果或失败原因。
  final String note;

  /// 模型最后那段话，最多留 4000 字。
  final String answer;
  final int steps;
  final int tokens;

  /// 补跑的那一次。
  final bool late;

  /// 错过了，没有跑。
  final bool missed;

  String get stamp => stampText(at);

  Map<String, Object?> toJson() => <String, Object?>{
        'at': at.toIso8601String(),
        'ok': ok,
        'note': note,
        if (answer.isNotEmpty) 'answer': answer,
        if (steps > 0) 'steps': steps,
        if (tokens > 0) 'tokens': tokens,
        if (late) 'late': true,
        if (missed) 'missed': true,
      };

  static TaskRun fromJson(Map<String, Object?> json) => TaskRun(
        at: DateTime.tryParse('${json['at'] ?? ''}') ?? DateTime.now(),
        ok: json['ok'] == true,
        note: '${json['note'] ?? ''}',
        answer: '${json['answer'] ?? ''}',
        steps: (json['steps'] as num?)?.toInt() ?? 0,
        tokens: (json['tokens'] as num?)?.toInt() ?? 0,
        late: json['late'] == true,
        missed: json['missed'] == true,
      );
}

/// 一个定时任务。字段都是可改的：编辑页改完直接存。
class ScheduledTask {
  ScheduledTask({
    required this.id,
    required this.title,
    required this.prompt,
    this.hostId = '',
    this.enabled = true,
    this.kind = ScheduleKind.daily,
    this.minuteOfDay = 180,
    List<int>? weekdays,
    this.intervalMinutes = 60,
    this.onceAt,
    DateTime? createdAt,
    this.nextAt,
    List<TaskRun>? runs,
  })  : weekdays = weekdays ?? <int>[1],
        createdAt = createdAt ?? DateTime.now(),
        runs = runs ?? <TaskRun>[];

  final String id;
  String title;
  String prompt;

  /// 空表示这个任务可以用全部主机，由模型自己挑。
  String hostId;
  bool enabled;
  ScheduleKind kind;

  /// 每天／每周的那个时刻，0 到 1439。
  int minuteOfDay;

  /// 1 = 周一 … 7 = 周日。
  List<int> weekdays;
  int intervalMinutes;
  DateTime? onceAt;

  /// 按间隔排的时候从这里起算，所以重启不会把节奏打乱。
  DateTime createdAt;

  /// 下一次该跑的时刻。null 表示不会再有下一次。
  DateTime? nextAt;

  /// 最新的在最前面。
  final List<TaskRun> runs;

  bool get multiHost => hostId.isEmpty;

  /// 只跑一次而且已经跑过了。
  bool get finished => kind == ScheduleKind.once && !enabled;

  int get intervalStep => intervalMinutes < 5 ? 5 : intervalMinutes;

  /// 按间隔排的时候，间隔写成「2 小时」比「120 分钟」好读。
  String get intervalText {
    final int m = intervalStep;
    if (m < 60) return '每 $m 分钟';
    if (m % 60 == 0) return '每 ${m ~/ 60} 小时';
    return '每 ${m ~/ 60} 小时 ${m % 60} 分';
  }

  /// 「每天 03:00」「每周二、周五 08:30」「每 2 小时」「一次 10-26 09:00」。
  String get when {
    switch (kind) {
      case ScheduleKind.daily:
        return '每天 ${clockText(minuteOfDay)}';
      case ScheduleKind.weekly:
        final List<int> days = List<int>.of(_days)..sort();
        final String names = days.map((int d) => kWeekNames[(d - 1).clamp(0, 6)]).join('、');
        return '每周$names ${clockText(minuteOfDay)}';
      case ScheduleKind.interval:
        return intervalText;
      case ScheduleKind.once:
        final DateTime? at = onceAt;
        return at == null ? '一次（还没定时间）' : '一次 ${stampText(at)}';
    }
  }

  List<int> get _days =>
      weekdays.isEmpty ? const <int>[1, 2, 3, 4, 5, 6, 7] : weekdays;

  int get _clockMinutes {
    final int m = minuteOfDay < 0 ? 0 : (minuteOfDay > 1439 ? 1439 : minuteOfDay);
    return m;
  }

  /// 严格晚于 [from] 的下一个时刻。null 表示不会再有。
  DateTime? nextRunAfter(DateTime from) {
    switch (kind) {
      case ScheduleKind.daily:
        final DateTime today = DateTime(
            from.year, from.month, from.day, _clockMinutes ~/ 60, _clockMinutes % 60);
        if (today.isAfter(from)) return today;
        return DateTime(from.year, from.month, from.day + 1, _clockMinutes ~/ 60,
            _clockMinutes % 60);
      case ScheduleKind.weekly:
        final List<int> days = _days;
        for (int i = 0; i <= 7; i += 1) {
          final DateTime day = DateTime(from.year, from.month, from.day + i);
          if (!days.contains(day.weekday)) continue;
          final DateTime at = DateTime(day.year, day.month, day.day, _clockMinutes ~/ 60,
              _clockMinutes % 60);
          if (at.isAfter(from)) return at;
        }
        return null;
      case ScheduleKind.interval:
        final int step = intervalStep;
        final DateTime anchor = createdAt;
        if (anchor.isAfter(from)) return anchor;
        final int passed = from.difference(anchor).inSeconds;
        final int slot = (passed ~/ (step * 60)) + 1;
        return anchor.add(Duration(minutes: step * slot));
      case ScheduleKind.once:
        final DateTime? at = onceAt;
        if (at == null) return null;
        return at.isAfter(from) ? at : null;
    }
  }

  /// 把下一次排到 [now] 之后。
  void scheduleFrom(DateTime now) {
    nextAt = nextRunAfter(now);
  }

  void addRun(TaskRun run) {
    runs.insert(0, run);
    while (runs.length > kMaxRuns) {
      runs.removeLast();
    }
  }

  TaskRun? get lastRun => runs.isEmpty ? null : runs.first;

  /// 还没有跑的、也没有错过的最近一条。
  TaskRun? get lastRealRun {
    for (final TaskRun r in runs) {
      if (!r.missed) return r;
    }
    return null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'prompt': prompt,
        'hostId': hostId,
        'enabled': enabled,
        'kind': kind.name,
        'minuteOfDay': minuteOfDay,
        'weekdays': weekdays,
        'intervalMinutes': intervalMinutes,
        if (onceAt != null) 'onceAt': onceAt!.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        if (nextAt != null) 'nextAt': nextAt!.toIso8601String(),
        'runs': runs.map((TaskRun r) => r.toJson()).toList(),
      };

  static ScheduledTask fromJson(Map<String, Object?> json) {
    final Object? rawDays = json['weekdays'];
    final Object? rawRuns = json['runs'];
    final List<TaskRun> runs = <TaskRun>[];
    if (rawRuns is List) {
      for (final Object? raw in rawRuns) {
        if (raw is Map) runs.add(TaskRun.fromJson(Map<String, Object?>.from(raw)));
      }
    }
    return ScheduledTask(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      prompt: '${json['prompt'] ?? ''}',
      hostId: '${json['hostId'] ?? ''}',
      enabled: json['enabled'] != false,
      kind: _kindOf('${json['kind'] ?? ''}'),
      minuteOfDay: (json['minuteOfDay'] as num?)?.toInt() ?? 180,
      weekdays: rawDays is List
          ? rawDays
              .map((Object? e) => (e is num) ? e.toInt() : int.tryParse('$e') ?? 0)
              .where((int d) => d >= 1 && d <= 7)
              .toList()
          : <int>[1],
      intervalMinutes: (json['intervalMinutes'] as num?)?.toInt() ?? 60,
      onceAt: DateTime.tryParse('${json['onceAt'] ?? ''}'),
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}') ?? DateTime.now(),
      nextAt: DateTime.tryParse('${json['nextAt'] ?? ''}'),
      runs: runs,
    );
  }

  static ScheduleKind _kindOf(String name) {
    for (final ScheduleKind k in ScheduleKind.values) {
      if (k.name == name) return k;
    }
    return ScheduleKind.daily;
  }

  /// 编辑完把下次时刻重排一次，顺手清掉不可能的过去时刻。
  void reschedule(DateTime now) {
    if (!enabled) {
      nextAt = null;
      return;
    }
    if (kind == ScheduleKind.once && (onceAt == null || !onceAt!.isAfter(now))) {
      // 定在过去的一次性任务不会再跑，就当它已经废了。
      enabled = false;
      nextAt = null;
      return;
    }
    scheduleFrom(now);
  }
}

/// 默认补跑窗口：错过三小时以内还补一次，再久就算了。
const Duration kCatchUpWindow = Duration(hours: 3);

/// 到点之后过了三分钟以上才算「补跑」，三分钟以内算准点。
const Duration kOnTimeSlack = Duration(minutes: 3);

/// 这一刻该不该跑这个任务。[now] 由调用方给，测试才好固定。
DueAction dueAction(ScheduledTask task, DateTime now, {Duration window = kCatchUpWindow}) {
  if (!task.enabled) return DueAction.none;
  final DateTime? due = task.nextAt;
  if (due == null) return DueAction.none;
  if (now.isBefore(due)) return DueAction.none;
  final Duration late = now.difference(due);
  if (late > window) return DueAction.skip;
  return late > kOnTimeSlack ? DueAction.runLate : DueAction.run;
}

/// 一句话结果：模型最后那段话的第一行，太长就截。
String summaryLine(String answer, {int max = 60}) {
  final String text = answer.trim();
  if (text.isEmpty) return '';
  for (final String line in text.split('\n')) {
    final String t = line.trim();
    if (t.isEmpty) continue;
    return t.length > max ? '${t.substring(0, max)}…' : t;
  }
  return '';
}
