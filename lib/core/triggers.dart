/// 触发器：条件满足时做一件事。
///
/// 三种条件：手机状态（由模型判断）、消息通知（关键词）、定时（每天几点或每隔几分钟）。
/// 动作两种：发一条通知、或者让模型跑一句提示词。
///
/// 这一层是纯 Dart：定义、匹配、排下一次、写给人看的那几句话，都在这里，
/// 界面和跑腿的分工放在外面。
library;

import 'phone_signals.dart';
import 'triggers_mention.dart';

/// 条件从哪儿来。
enum TriggerKind { phone, message, schedule }

/// 满足了做什么。
enum TriggerActionKind { notify, prompt, openApp }

/// 一次运行的结果。
enum TriggerRunStatus { fired, skipped, failed, waiting }

String triggerKindName(TriggerKind kind) => switch (kind) {
      TriggerKind.phone => '手机状态',
      TriggerKind.message => '消息通知',
      TriggerKind.schedule => '定时',
    };

String triggerStatusName(TriggerRunStatus status) => switch (status) {
      TriggerRunStatus.fired => '已执行',
      TriggerRunStatus.skipped => '没触发',
      TriggerRunStatus.failed => '失败',
      TriggerRunStatus.waiting => '等你确认',
    };

String triggerActionName(TriggerActionKind kind) => switch (kind) {
      TriggerActionKind.notify => '发通知',
      TriggerActionKind.prompt => '让模型跑一句',
      TriggerActionKind.openApp => '打开应用',
    };

/// 手机状态里能让 AI 参考的那几项。名字与 [PhoneSignals] 的字段一致。
class SignalOption {
  const SignalOption(this.key, this.label);

  final String key;
  final String label;
}

const List<SignalOption> kSignalOptions = <SignalOption>[
  SignalOption('charging', '充电'),
  SignalOption('battery', '电量'),
  SignalOption('network', '网络类型'),
  SignalOption('screenOn', '亮屏'),
  SignalOption('locked', '锁屏'),
  SignalOption('headset', '耳机'),
  SignalOption('ringer', '静音'),
  SignalOption('dnd', '勿扰'),
  SignalOption('music', '在放音乐'),
];

String signalLabel(String key) {
  for (final SignalOption s in kSignalOptions) {
    if (s.key == key) return s.label;
  }
  return key;
}

/// 一次运行。
class TriggerRun {
  TriggerRun({required this.at, required this.status, this.note = ''});

  final DateTime at;
  final TriggerRunStatus status;
  final String note;

  Map<String, Object?> toJson() => <String, Object?>{
        'at': at.toIso8601String(),
        'status': status.name,
        if (note.isNotEmpty) 'note': note,
      };

  static TriggerRun fromJson(Map<String, Object?> json) => TriggerRun(
        at: DateTime.tryParse('${json['at'] ?? ''}') ?? DateTime.now(),
        status: TriggerRunStatus.values.firstWhere(
          (TriggerRunStatus s) => s.name == '${json['status'] ?? ''}',
          orElse: () => TriggerRunStatus.skipped,
        ),
        note: '${json['note'] ?? ''}',
      );
}

/// 一个触发器。
class Trigger {
  Trigger({
    required this.id,
    this.name = '',
    this.kind = TriggerKind.phone,
    this.enabled = false,
    this.intent = '',
    List<String>? signals,
    this.atTime = '',
    this.everyMinutes = 15,
    this.action = TriggerActionKind.notify,
    this.actionText = '',
    this.confirm = false,
    this.allowWrite = true,
    List<String>? myNames,
    this.nextAt,
    this.lastAt,
    List<TriggerRun>? runs,
  })  : signals = signals ?? <String>[],
        myNames = myNames ?? <String>[],
        runs = runs ?? <TriggerRun>[];

  String id;
  String name;
  TriggerKind kind;
  bool enabled;

  /// 手机状态：让模型判断的意图，一句话。
  /// 消息通知：关键词，逗号或空格分开。
  String intent;

  /// 手机状态：允许参考哪几项。空着表示全都允许（系统给了才算）。
  List<String> signals;

  /// 定时：`08:30` 每天这个点；空着就按 [everyMinutes] 隔多久一次。
  String atTime;

  /// 手机状态判多久看一次；定时没写 [atTime] 时也用它。
  int everyMinutes;

  TriggerActionKind action;

  /// 通知正文，或者交给模型的那句提示词。
  String actionText;

  /// 真要做之前先问一句。
  bool confirm;

  /// 自动跑起来时，要确认的那些操作放不放行。
  /// 会把机器弄坏的那一档在策略层就拦下了，这里开着也做不了。
  bool allowWrite;

  /// 消息通知：我是谁。昵称、呼号、备注名都写这儿，逗号分开。
  ///
  /// 群里有人 @ 我才算冲着我来的；不写这一项就只看关键词，
  /// 那意味着群里谁说脏话都算。
  List<String> myNames;

  DateTime? nextAt;
  DateTime? lastAt;

  /// 最近若干次，新的在前，最多留 [maxRuns] 条。
  final List<TriggerRun> runs;

  /// 每一条留多少次记录。触发器比任务看得勤，留得多一点才看得出规律。
  static const int maxRuns = 100;

  String get title => name.trim().isEmpty ? triggerKindName(kind) : name.trim();

  /// 消息关键词拆出来。中英文逗号、分号、空白都算分隔。
  List<String> get keywords => intent
      .split(RegExp(r'[,，;；\s]+'))
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList();

  /// 这一项信号是不是允许看。
  bool allowsSignal(String key) => signals.isEmpty || signals.contains(key);

  /// 这次判断要不要问一句。
  bool get needsConfirm => confirm && action == TriggerActionKind.prompt;

  void addRun(TriggerRun run) {
    runs.insert(0, run);
    if (runs.length > maxRuns) runs.removeRange(maxRuns, runs.length);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'kind': kind.name,
        'enabled': enabled,
        'intent': intent,
        if (signals.isNotEmpty) 'signals': signals,
        'atTime': atTime,
        'everyMinutes': everyMinutes,
        'action': action.name,
        'actionText': actionText,
        if (confirm) 'confirm': true,
        if (!allowWrite) 'allowWrite': false,
        if (myNames.isNotEmpty) 'myNames': myNames,
        if (nextAt != null) 'nextAt': nextAt!.toIso8601String(),
        if (lastAt != null) 'lastAt': lastAt!.toIso8601String(),
        if (runs.isNotEmpty) 'runs': runs.map((TriggerRun r) => r.toJson()).toList(),
      };

  static Trigger fromJson(Map<String, Object?> json) {
    final Object? rawSignals = json['signals'];
    final Object? rawMyNames = json['myNames'];
    final Object? rawRuns = json['runs'];
    final List<TriggerRun> runs = <TriggerRun>[];
    if (rawRuns is List) {
      for (final Object? raw in rawRuns) {
        if (raw is Map) runs.add(TriggerRun.fromJson(Map<String, Object?>.from(raw)));
      }
    }
    return Trigger(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      kind: TriggerKind.values.firstWhere(
        (TriggerKind k) => k.name == '${json['kind'] ?? ''}',
        orElse: () => TriggerKind.phone,
      ),
      enabled: json['enabled'] == true,
      intent: '${json['intent'] ?? ''}',
      signals: rawSignals is List
          ? rawSignals.map((Object? e) => '$e').where((String s) => s.isNotEmpty).toList()
          : <String>[],
      atTime: '${json['atTime'] ?? ''}',
      everyMinutes: (json['everyMinutes'] as num?)?.toInt() ?? 15,
      action: TriggerActionKind.values.firstWhere(
        (TriggerActionKind a) => a.name == '${json['action'] ?? ''}',
        orElse: () => TriggerActionKind.notify,
      ),
      actionText: '${json['actionText'] ?? ''}',
      confirm: json['confirm'] == true,
      // 没写这一项的是老文件，按能动手算，行为与以前一样。
      allowWrite: json['allowWrite'] != false,
      // 没写「我是谁」的老文件也照样能用：那就退回只看关键词。
      myNames: rawMyNames is List
          ? rawMyNames.map((Object? e) => '$e').where((String s) => s.trim().isNotEmpty).toList()
          : <String>[],
      nextAt: DateTime.tryParse('${json['nextAt'] ?? ''}'),
      lastAt: DateTime.tryParse('${json['lastAt'] ?? ''}'),
      runs: runs,
    );
  }
}

/// `08:30` → 今天/明天那个时刻里最近的一个。
DateTime? atTimeNext(String atTime, DateTime from) {
  final Match? m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(atTime.trim());
  if (m == null) return null;
  final int hour = int.parse(m.group(1)!);
  final int minute = int.parse(m.group(2)!);
  if (hour > 23 || minute > 59) return null;
  DateTime at = DateTime(from.year, from.month, from.day, hour, minute);
  if (!at.isAfter(from)) at = at.add(const Duration(days: 1));
  return at;
}

/// 下一次该在什么时候看它。
DateTime? nextDueAt(Trigger t, DateTime from) {
  if (t.kind == TriggerKind.schedule && t.atTime.trim().isNotEmpty) {
    final DateTime? daily = atTimeNext(t.atTime, from);
    if (daily != null) {
      final DateTime? old = t.nextAt;
      if (old != null && old.isAfter(from)) return old;
      return daily;
    }
  }
  final int every = t.everyMinutes < 1 ? 1 : t.everyMinutes;
  final DateTime? old = t.nextAt;
  if (old != null && old.isAfter(from)) return old;
  return from.add(Duration(minutes: every));
}

/// 一条通知算不算碰上关键词。有大写就按大小写算一遍，没有就忽略大小写。
bool keywordHit(Trigger t, String title, String text) {
  final List<String> words = t.keywords;
  if (words.isEmpty) return false;
  final String haystack = '$title\n$text';
  final String lower = haystack.toLowerCase();
  for (final String w in words) {
    if (haystack.contains(w) || lower.contains(w.toLowerCase())) return true;
  }
  return false;
}

/// 一条通知算不算「冲着我来的」。
///
/// 写清楚了「我是谁」（[Trigger.myNames]）的话，还得看这条是不是冲着主人来的：
/// 群里别人跟别人斗嘴，不该由主人来接话。
bool messageMatches(Trigger t, String title, String text) {
  if (!keywordHit(t, title, text)) return false;
  // 没写「我是谁」就只看关键词，行为跟以前一样。
  if (t.myNames.isEmpty) return true;
  return judgeTarget(title: title, text: text, myNames: t.myNames).atMe;
}

/// 说得清为什么算冲着我来的，主人一看就懂。
String targetReason(Trigger t, String title, String text) {
  if (t.myNames.isEmpty) return '碰上关键词';
  final MessageTarget j = judgeTarget(title: title, text: text, myNames: t.myNames);
  return j.atMe ? '冲着我说的（${j.reason}）' : '不是冲着我说的';
}

/// 消息通知要比对的那一段：上一次看到现在。
///
/// 没有上一次、时间反了（改过系统时间）、或者隔得太久，就各自退回去：
/// 半小时、半小时、最多十二小时。调用前把 lastAt 当成「上一次」传进来，
/// 不能先把它挪到这一次，否则这一段永远是空的。
DateTime messageSince(DateTime at, DateTime? previous) {
  final DateTime fallback = at.subtract(const Duration(minutes: 30));
  if (previous == null) return fallback;
  if (previous.isAfter(at)) return fallback;
  final DateTime oldest = at.subtract(const Duration(hours: 12));
  if (previous.isBefore(oldest)) return oldest;
  return previous;
}

/// 交给模型看的状态清单：只写它被允许看的那几项。
String signalsForPrompt(Trigger t, PhoneSignals s) {
  final List<String> lines = <String>[];
  if (t.allowsSignal('battery') && s.battery >= 0) lines.add('电量：${s.battery}%');
  if (t.allowsSignal('charging')) lines.add('充电：${s.charging ? '在充电' : '没充电'}');
  if (t.allowsSignal('network') && s.network.isNotEmpty) {
    lines.add('网络：${switch (s.network) {
      'wifi' => '无线',
      'mobile' => '移动数据',
      'ethernet' => '网线',
      'vpn' => 'VPN',
      'offline' => '没联网',
      _ => s.network,
    }}');
  }
  if (t.allowsSignal('screenOn') && s.screenOn != null) {
    lines.add('屏幕：${s.screenOn! ? '亮着' : '黑着'}');
  }
  if (t.allowsSignal('locked') && s.locked != null) {
    lines.add('锁屏：${s.locked! ? '锁着' : '已解锁'}');
  }
  if (t.allowsSignal('headset') && s.headset != null) {
    lines.add('耳机：${s.headset! ? '连着' : '没连'}');
  }
  if (t.allowsSignal('ringer') && s.ringer.isNotEmpty) {
    lines.add('铃音：${switch (s.ringer) {
      'silent' => '静音',
      'vibrate' => '振动',
      _ => '响铃',
    }}');
  }
  if (t.allowsSignal('dnd') && s.dnd != null) {
    lines.add('勿扰：${s.dnd! ? '开着' : '没开'}');
  }
  if (t.allowsSignal('music') && s.music != null) {
    lines.add('在放音乐：${s.music! ? '是' : '不是'}');
  }
  return lines.isEmpty ? '（没有可参考的信号）' : lines.join('\n');
}

/// 模型判断手机状态时用的那套话。要求它只回一行 JSON。
const String kPhoneJudgeSystem = '''
你在判断一部手机此刻的状态符不符合用户设的触发条件。
只根据给定的信号判断，不要猜没有给的东西。
只回一行 JSON，不要解释，不要代码块：
{"match": true 或 false, "reason": "一句话依据", "confidence": 0.0 到 1.0}
拿不准就 match=false，confidence 写低一点。''';

/// 用户那段意图 + 这次读到的信号，拼成请求正文。
String phoneJudgePrompt(Trigger t, PhoneSignals s, DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '触发条件：${t.intent.trim().isEmpty ? '（用户没写）' : t.intent.trim()}\n'
      '现在：${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}\n'
      '手机状态：\n${signalsForPrompt(t, s)}';
}

/// 模型那一行 JSON 读回来。
class PhoneJudge {
  const PhoneJudge({required this.match, required this.reason, this.confidence = 0});

  final bool match;
  final String reason;
  final double confidence;

  String get text => '${match ? '触发' : '不触发'}：$reason'
      '${confidence > 0 ? '（把握 ${(confidence * 100).round()}%）' : ''}';
}

/// 解析模型那一行。读不像就当成不触发，并把原文写进理由里。
PhoneJudge parseJudge(String raw) {
  final String text = raw.trim();
  final int start = text.indexOf('{');
  final int end = text.lastIndexOf('}');
  if (start < 0 || end <= start) {
    return PhoneJudge(match: false, reason: '模型没给出可读的判断');
  }
  final String body = text.substring(start, end + 1);
  bool match = false;
  String reason = '';
  double confidence = 0;
  final Match? m = RegExp(r'"match"\s*:\s*(true|false)').firstMatch(body);
  if (m != null) match = m.group(1) == 'true';
  final Match? r = RegExp(r'"reason"\s*:\s*"([^"]*)"').firstMatch(body);
  if (r != null) reason = r.group(1) ?? '';
  final Match? c = RegExp(r'"confidence"\s*:\s*([0-9.]+)').firstMatch(body);
  if (c != null) confidence = double.tryParse(c.group(1)!) ?? 0;
  if (reason.isEmpty) reason = match ? '条件满足' : '条件不满足';
  return PhoneJudge(match: match, reason: reason, confidence: confidence.clamp(0, 1));
}
