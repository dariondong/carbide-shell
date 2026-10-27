import '../core/models.dart';
import '../core/rules.dart';
import '../core/schedule.dart';
import '../core/tools.dart';
import '../core/watch.dart';
import '../data/hosts.dart';
import '../data/tasks.dart';
import '../data/watch.dart';

/// `task_add`：让模型自己排一条定时任务。
///
/// 写操作，审批卡上会说清楚排的是什么。到点后由调度器跑，那时候没人确认，
/// 所以建之前先把要做的事写清楚。
class TaskAddTool extends Tool {
  TaskAddTool({required this.tasks, required this.hosts});

  final TaskStore tasks;
  final HostStore hosts;

  @override
  String get name => 'task_add';

  @override
  String get description =>
      '排一条定时任务：到点让助手自己去做一件事。要写清楚做什么（会原样当成那一轮的指令）。'
      '要「磁盘超过 90% 才清」这种判断，就把条件写进 conditions，到点先读数字，符合了才叫模型。'
      '条件可以是几条判断用 且 / 或 和括号连起来，比如 disk>90 且 (cpu>80 或 memory>=85)。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'title': <String, Object?>{'type': 'string', 'description': '名字，比如 磁盘体检'},
          'prompt': <String, Object?>{'type': 'string', 'description': '到点要做的事，一句话写清楚'},
          'kind': <String, Object?>{
            'type': 'string',
            'enum': <String>['daily', 'weekly', 'interval', 'once'],
            'description': 'daily 每天，weekly 每周，interval 每隔一阵，once 只跑一次',
          },
          'time': <String, Object?>{'type': 'string', 'description': 'daily 和 weekly 用的时刻，24 小时制 HH:MM'},
          'weekdays': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'integer'},
            'description': 'weekly 用，1 是周一，7 是周日',
          },
          'interval_minutes': <String, Object?>{'type': 'integer', 'description': 'interval 用，多少分钟一次'},
          'once_at': <String, Object?>{'type': 'string', 'description': 'once 用，本地时间 2026-10-26 09:00'},
          'host': <String, Object?>{'type': 'string', 'description': '只管一台时写主机名，留空表示全部主机'},
          'conditions': <String, Object?>{
            'description': '先看条件，空表示到点直接跑。三种写法都认：'
                '一整句 disk>90 且 (cpu>80 或 memory>=85)；'
                '一组句子 ["disk>90", "cpu>80"] 按 condition_logic 连；'
                '或者一棵树 {"logic":"any","children":[{...}]}，树上的叶子写成 '
                '{"metric":"disk","op":"gt","value":90}，metric 认 cpu/memory/disk/swap/load',
          },
          'condition_logic': <String, Object?>{
            'type': 'string',
            'enum': <String>['all', 'any'],
            'description': 'conditions 给了几条平的条件时怎么连：all 全部满足（默认），any 满足一条就够',
          },
          'gate_retry_minutes': <String, Object?>{
            'type': 'integer',
            'description': '条件没满足时隔几分钟再看一次，默认 5',
          },
          'gate_window_minutes': <String, Object?>{
            'type': 'integer',
            'description': '到点后最多等多少分钟，过了这一轮就不跑，默认 60；0 表示只看一次',
          },
        },
        'required': <String>['title', 'prompt', 'kind'],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.write;

  @override
  String summarize(Map<String, Object?> args) {
    final String title = readString(args, 'title');
    final String kind = readString(args, 'kind', fallback: 'daily');
    final String time = readString(args, 'time');
    final String every = readString(args, 'interval_minutes');
    final String when = switch (kind) {
      'weekly' => '每周 ${time.isEmpty ? '没写时刻' : time}',
      'interval' => '每 ${every.isEmpty ? '60' : every} 分钟',
      'once' => '一次 ${readString(args, 'once_at')}',
      _ => '每天 ${time.isEmpty ? '没写时刻' : time}',
    };
    return '加定时任务 $title · $when${_conditionsBrief(args)}';
  }

  /// 审批卡上把条件一并念出来。
  static String _conditionsBrief(Map<String, Object?> args) {
    final Object? read = _conditionOf(args);
    if (read is! RuleNode) return '';
    return ' · 满足 ${conditionTextOf(read)} 才跑';
  }

  /// 把 conditions 读成一棵树。读不出来返回一句说明（String）。
  ///
  /// 三种写法：一整句带 且/或/括号，一组句子，或者一棵树。
  static Object? _conditionOf(Map<String, Object?> args) {
    final Object? raw = args['conditions'];
    final RuleLogic logic =
        readString(args, 'condition_logic', fallback: 'all') == 'any'
            ? RuleLogic.any
            : RuleLogic.all;
    if (raw == null) return null;
    if (raw is String) {
      final String text = raw.trim();
      if (text.isEmpty) return null;
      final RuleNode? node = parseCondition(text);
      return node ?? '条件写得认不出来：$text。写成 disk>90 且 (cpu>80 或 memory>=85) 这样。';
    }
    if (raw is Map) {
      final RuleNode? node = RuleNode.fromJson(raw);
      return node ?? '条件这棵树读不出来，叶子要写 metric/op/value。';
    }
    if (raw is! List) return '条件要写成一句、一组或者一棵树。';
    final List<RuleNode> children = <RuleNode>[];
    for (final Object? item in raw) {
      if (item is String) {
        final RuleNode? node = parseCondition(item);
        if (node == null) return '条件「$item」读不出来，写成 disk>90 这样。';
        children.add(node);
        continue;
      }
      if (item is Map) {
        final RuleNode? node = RuleNode.fromJson(item);
        if (node == null) return '条件里的这一项读不出来：$item';
        children.add(node);
      }
    }
    if (children.isEmpty) return null;
    if (children.length == 1) return children.first;
    return RuleNode.group(logic: logic, children: children);
  }
  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String title = readString(args, 'title').trim();
    final String prompt = readString(args, 'prompt').trim();
    if (title.isEmpty || prompt.isEmpty) {
      return const ToolOutcome.failure('名字和要做的事都要写。');
    }
    final String kindText = readString(args, 'kind', fallback: 'daily');
    ScheduleKind kind = ScheduleKind.daily;
    for (final ScheduleKind k in ScheduleKind.values) {
      if (k.name == kindText) kind = k;
    }

    final String hostName = readString(args, 'host').trim();
    String hostId = '';
    if (hostName.isNotEmpty) {
      final HostEntry? host = hosts.byName(hostName);
      if (host == null) {
        return ToolOutcome.failure('主机列表里没有叫 $hostName 的机器。');
      }
      hostId = host.id;
    }

    // 条件：写得出来的才算条件。
    final Object? read = _conditionOf(args);
    if (read is String) return ToolOutcome.failure(read);
    final RuleNode? condition = read is RuleNode ? read.collapse() : null;
    if (condition != null && hostId.isEmpty) {
      return const ToolOutcome.failure('要看条件就得写一个主机名，条件读的是那一台机器。');
    }

    int minuteOfDay = 180;
    final String time = readString(args, 'time').trim();
    if (time.isNotEmpty) {
      final int? parsed = parseClock(time);
      if (parsed == null) return ToolOutcome.failure('时刻写成 HH:MM 的样子，比如 03:00。');
      minuteOfDay = parsed;
    }

    final List<int> weekdays = <int>[];
    final Object? rawDays = args['weekdays'];
    if (rawDays is List) {
      for (final Object? raw in rawDays) {
        final int? day = raw is num ? raw.toInt() : int.tryParse('$raw');
        if (day != null && day >= 1 && day <= 7) weekdays.add(day);
      }
    }

    DateTime? onceAt;
    final String onceText = readString(args, 'once_at').trim();
    if (onceText.isNotEmpty) {
      onceAt = parseMoment(onceText);
      if (onceAt == null) {
        return const ToolOutcome.failure('时间写成 2026-10-26 09:00 这样。');
      }
    }

    final ScheduledTask task = ScheduledTask(
      id: TaskStore.newId(),
      title: title,
      prompt: prompt,
      hostId: hostId,
      kind: kind,
      minuteOfDay: minuteOfDay,
      weekdays: weekdays.isEmpty ? <int>[1] : weekdays,
      intervalMinutes: readInt(args, 'interval_minutes', fallback: 60),
      onceAt: onceAt,
      condition: condition,
      gateRetryMinutes: readInt(args, 'gate_retry_minutes', fallback: 5),
      gateWindowMinutes: readInt(args, 'gate_window_minutes', fallback: 60),
    );
    task.reschedule(DateTime.now());
    if (task.nextAt == null) {
      return const ToolOutcome.failure('这条排不出下一次：时间已经过去了，或者没写时刻。');
    }
    await tasks.upsert(task);
    final String gate = condition == null
        ? ''
        : '\n条件：${conditionTextOf(condition)}，到点先读，符合了才动手。';
    return ToolOutcome.success(
      stdout: '排好了：${task.title} · ${task.when}$gate\n'
          '下次 ${stampText(task.nextAt!)}。要不要现在先试一次，让用户自己决定。',
    );
  }
}

/// `watch_add`：让模型排一条资源监听。只看数字，不叫模型。
class WatchAddTool extends Tool {
  WatchAddTool({required this.watches, required this.hosts});

  final WatchStore watches;
  final HostStore hosts;

  @override
  String get name => 'watch_add';

  @override
  String get description =>
      '排一条监听：每隔一阵读一次某台机器的 CPU、内存、磁盘、交换、负载，或者失败登录次数、'
      '没见过的来源登录，过了线就给手机发一条通知。这个不叫模型，只看数字和登录记录。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'host': <String, Object?>{'type': 'string', 'description': '主机名，必须指定一台'},
          'kind': <String, Object?>{
            'type': 'string',
            'enum': <String>['metric', 'loginFail', 'loginNew'],
            'description': 'metric 看资源指标，loginFail 看失败登录次数，loginNew 看没见过的来源登录',
          },
          'metric': <String, Object?>{
            'type': 'string',
            'enum': <String>['cpu', 'memory', 'disk', 'swap', 'load'],
            'description': 'kind 是 metric 时看哪一项',
          },
          'window_minutes': <String, Object?>{
            'type': 'integer',
            'description': 'loginFail 的回看窗口，默认 10 分钟',
          },
          'above': <String, Object?>{'type': 'boolean', 'description': 'true 超过阈值提醒，false 低于阈值提醒'},
          'threshold': <String, Object?>{'type': 'number', 'description': '百分比，或者负载的那个数'},
          'interval_minutes': <String, Object?>{'type': 'integer', 'description': '多少分钟读一次，默认 5'},
          'cooldown_minutes': <String, Object?>{'type': 'integer', 'description': '提醒过之后歇多久，默认 30'},
          'title': <String, Object?>{'type': 'string', 'description': '通知上的名字，留空用主机名'},
        },
        'required': <String>['host', 'metric', 'threshold'],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.write;

  @override
  String summarize(Map<String, Object?> args) {
    final String host = readString(args, 'host');
    final WatchKind kind = _kindOf(readString(args, 'kind'));
    switch (kind) {
      case WatchKind.loginFail:
        final double threshold = _doubleOf(args['threshold'], 10);
        return '加监听 $host ${readInt(args, 'window_minutes', fallback: 10)} 分钟内'
            '失败登录 ≥ ${WatchTask.numberText(threshold)} 次';
      case WatchKind.loginNew:
        return '加监听 $host 新 IP 登录';
      case WatchKind.metric:
        final WatchMetric metric = _metricOf(readString(args, 'metric'));
        final bool above = args['above'] != false;
        final double threshold = _doubleOf(args['threshold'], 90);
        return '加监听 $host ${kWatchNames[metric]} ${above ? '>' : '<'} '
            '${WatchTask.numberText(threshold)}';
    }
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final HostEntry? host = hosts.byName(readString(args, 'host'));
    if (host == null) {
      return ToolOutcome.failure('主机列表里没有这台。先问用户是哪一台。');
    }
    final double threshold = _doubleOf(args['threshold'], double.nan);
    if (threshold.isNaN) return const ToolOutcome.failure('阈值要是一个数。');
    final WatchTask watch = WatchTask(
      id: WatchStore.newId(),
      title: readString(args, 'title').trim().isEmpty ? host.name : readString(args, 'title').trim(),
      hostId: host.id,
      kind: _kindOf(readString(args, 'kind')),
      metric: _metricOf(readString(args, 'metric')),
      windowMinutes: readInt(args, 'window_minutes', fallback: 10),
      above: args['above'] != false,
      threshold: threshold,
      intervalMinutes: readInt(args, 'interval_minutes', fallback: 5),
      cooldownMinutes: readInt(args, 'cooldown_minutes', fallback: 30),
    );
    watch.scheduleFrom(DateTime.now());
    await watches.upsert(watch);
    return ToolOutcome.success(
      stdout: '加好了：${watch.title} · ${watch.when}\n过线会直接推一条通知到手机，不叫模型。',
    );
  }

  static WatchKind _kindOf(String name) {
    for (final WatchKind k in WatchKind.values) {
      if (k.name == name.trim()) return k;
    }
    return WatchKind.metric;
  }

  static WatchMetric _metricOf(String name) {
    for (final WatchMetric m in WatchMetric.values) {
      if (m.name == name.trim().toLowerCase()) return m;
    }
    return WatchMetric.disk;
  }

  static double _doubleOf(Object? raw, double fallback) {
    if (raw is num) return raw.toDouble();
    return double.tryParse('$raw') ?? fallback;
  }
}

/// `03:00` 读成第几分钟。读不出来给 null。
int? parseClock(String text) {
  final Match? match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text.trim());
  if (match == null) return null;
  final int hour = int.parse(match.group(1)!);
  final int minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) return null;
  return hour * 60 + minute;
}

/// `2026-10-26 09:00` 读成本地时刻。也认 `2026-10-26T09:00`。
DateTime? parseMoment(String text) {
  final String raw = text.trim().replaceFirst(' ', 'T');
  final Match? match =
      RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})T(\d{1,2}):(\d{2})$').firstMatch(raw);
  if (match == null) return DateTime.tryParse(text.trim());
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
  );
}
