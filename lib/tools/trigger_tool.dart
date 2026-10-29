import '../core/models.dart';
import '../core/tools.dart';
import '../core/triggers.dart';
import '../data/triggers.dart';

/// `trigger_list`：让模型看见已经配好的触发器。
///
/// 只读。改了清单之前先看一眼，免得同一条被写两遍。
class TriggerListTool extends Tool {
  TriggerListTool(this.triggers);

  final TriggerStore triggers;

  @override
  String get name => 'trigger_list';

  @override
  String get description => '列出已经配好的触发器：什么条件、做什么、开着没有、最近跑成什么样。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.read;

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final List<Trigger> list = triggers.all;
    if (list.isEmpty) return const ToolOutcome.success(stdout: '还没有触发器。');
    final StringBuffer b = StringBuffer('${list.length} 条触发器\n');
    for (final Trigger t in list) {
      b.writeln('- ${t.title}：${triggerKindName(t.kind)}，${_conditionOf(t)}，'
          '${triggerActionName(t.action)}${t.actionText.trim().isEmpty ? '' : '「${_clip(t.actionText, 40)}」'}，'
          '${t.enabled ? '开着' : '已关'}'
          '${t.runs.isEmpty ? '' : '，上回 ${triggerStatusName(t.runs.first.status)}：${_clip(t.runs.first.note, 30)}'}'
          '（id ${t.id}）');
    }
    return ToolOutcome.success(stdout: b.toString().trimRight());
  }
}

/// `trigger_save`：新建或改一条触发器。
///
/// 写操作，审批卡上会把条件和动作念一遍再动手。到点跑的时候没有人守在旁边，
/// 所以条件与要做什么都得写清楚。
class TriggerSaveTool extends Tool {
  TriggerSaveTool(this.triggers);

  final TriggerStore triggers;

  @override
  String get name => 'trigger_save';

  @override
  String get description =>
      '新建或修改一条触发器：条件满足时做一件事。三种条件：手机状态（由模型判断一句话）、'
      '消息通知（关键词）、定时（每天几点或每隔几分钟）；动作两种：发一条通知、或者让模型跑一句提示词。'
      '给了 id 就是改那一条；没给 id 但名字撞上已有的一条，也是改那一条；都没有就是新建。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'id': <String, Object?>{'type': 'string', 'description': '要改的那一条的 id，trigger_list 里看到的'},
          'name': <String, Object?>{'type': 'string', 'description': '名字，比如 到家提醒'},
          'kind': <String, Object?>{
            'type': 'string',
            'enum': <String>['phone', 'message', 'schedule'],
            'description': 'phone 看手机状态，message 看通知关键词，schedule 到点就跑',
          },
          'intent': <String, Object?>{
            'type': 'string',
            'description': 'phone 写一句要看的状态，比如「到家了在充电」；message 写关键词，逗号分开',
          },
          'signals': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
            'description': 'phone 用：允许模型参考哪几项。可选 charging/battery/network/screenOn/'
                'locked/headset/ringer/dnd/music，留空表示全都允许',
          },
          'at_time': <String, Object?>{'type': 'string', 'description': 'schedule 用：每天几点，HH:MM'},
          'every_minutes': <String, Object?>{
            'type': 'integer',
            'description': '多久看一次，默认 15。schedule 没写 at_time 时按这个间隔跑',
          },
          'action': <String, Object?>{
            'type': 'string',
            'enum': <String>['notify', 'prompt'],
            'description': 'notify 发一条通知，prompt 让模型跑一句话',
          },
          'action_text': <String, Object?>{
            'type': 'string',
            'description': 'notify 写通知正文；prompt 写交给模型的那句话（会原样当成那一轮的指令）',
          },
          'confirm': <String, Object?>{
            'type': 'boolean',
            'description': 'prompt 用：条件满足了先弹一条通知等用户点一下，再让模型跑',
          },
          'enabled': <String, Object?>{'type': 'boolean', 'description': '建好就开着，默认开'},
        },
        'required': <String>['name'],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.write;

  @override
  bool get alwaysAsk => true;

  @override
  String summarize(Map<String, Object?> args) {
    final Trigger? old = _existing(args);
    final String verb = old == null ? '新建触发器' : '改触发器';
    final String kind = readString(args, 'kind', fallback: old?.kind.name ?? 'phone');
    final String condition = switch (kind) {
      'message' => '通知碰上「${readString(args, 'intent', fallback: old?.intent ?? '')}」',
      'schedule' => _scheduleText(args, old),
      _ => '手机状态：${readString(args, 'intent', fallback: old?.intent ?? '')}',
    };
    final String action =
        readString(args, 'action', fallback: old?.action.name ?? 'notify') == 'prompt'
            ? '让模型跑一句'
            : '发一条通知';
    return '$verb ${readString(args, 'name', fallback: old?.name ?? '')} · $condition → $action';
  }

  Trigger? _existing(Map<String, Object?> args) {
    final String id = readString(args, 'id').trim();
    if (id.isNotEmpty) return triggers.byId(id);
    final String name = readString(args, 'name').trim();
    if (name.isEmpty) return null;
    for (final Trigger t in triggers.all) {
      if (t.name == name) return t;
    }
    return null;
  }

  static String _scheduleText(Map<String, Object?> args, Trigger? old) {
    final String time = readString(args, 'at_time', fallback: old?.atTime ?? '').trim();
    if (time.isNotEmpty) return '每天 $time';
    final int every = readInt(args, 'every_minutes', fallback: old?.everyMinutes ?? 15);
    return '每 $every 分钟';
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String id = readString(args, 'id').trim();
    if (id.isNotEmpty && triggers.byId(id) == null) {
      return ToolOutcome.failure('没有 id 是 $id 的触发器。先用 trigger_list 看一眼。');
    }
    final Trigger? old = _existing(args);
    final Trigger t = old == null
        ? Trigger(id: triggers.nextId())
        : Trigger.fromJson(old.toJson());

    // 只认这次给了的参数，没写的照旧。
    void put(String key, void Function(Object? value) apply) {
      if (args.containsKey(key)) apply(args[key]);
    }

    put('name', (Object? v) => t.name = '${v ?? ''}'.trim());
    put('kind', (Object? v) => t.kind = _kindOf('$v', t.kind));
    put('intent', (Object? v) => t.intent = '${v ?? ''}'.trim());
    put('action', (Object? v) => t.action = _actionOf('$v', t.action));
    put('action_text', (Object? v) => t.actionText = '${v ?? ''}'.trim());
    put('confirm', (Object? v) => t.confirm = v == true);
    put('at_time', (Object? v) => t.atTime = '${v ?? ''}'.trim());
    put('every_minutes', (Object? v) {
      final int minutes = v is num ? v.toInt() : int.tryParse('$v') ?? t.everyMinutes;
      t.everyMinutes = minutes < 1 ? 1 : minutes;
    });
    put('signals', (Object? v) {
      if (v is! List) return;
      t.signals = v
          .map((Object? e) => '$e'.trim())
          .where((String s) => s.isNotEmpty)
          .toList();
    });

    final bool enabled = args.containsKey('enabled') ? args['enabled'] == true : (old?.enabled ?? true);
    t.enabled = enabled;

    final String bad = _check(t);
    if (bad.isNotEmpty) return ToolOutcome.failure(bad);

    t.nextAt = enabled ? nextDueAt(t, DateTime.now()) : null;
    await triggers.upsert(t);
    final String head = old == null ? '加好了' : '改好了';
    return ToolOutcome.success(
      stdout: '$head：${t.title} · ${_conditionOf(t)} → '
          '${triggerActionName(t.action)}${t.actionText.trim().isEmpty ? '' : '「${_clip(t.actionText, 40)}」'}\n'
          '${t.enabled ? '开着，' : '还关着，'}${t.nextAt == null ? '没有排下一次。' : '下一次看它：${_stamp(t.nextAt!)}。'}'
          '${t.action == TriggerActionKind.prompt ? '\n跑的时候没有人回答，需要确认的操作会被拒绝。' : ''}',
    );
  }

  /// 触发器要能自己跑起来，条件与动作都不能空着。
  static String _check(Trigger t) {
    if (t.name.isEmpty) return '名字要写，不然列表里认不出是哪一条。';
    switch (t.kind) {
      case TriggerKind.phone:
        if (t.intent.isEmpty) return '手机状态这一类要写一句看什么，比如「到家了在充电」。';
      case TriggerKind.message:
        if (t.keywords.isEmpty) return '消息通知这一类要写关键词，逗号分开。';
      case TriggerKind.schedule:
        if (t.atTime.isEmpty && t.everyMinutes < 1) {
          return '定时这一类要写每天几点（HH:MM），或者每隔多少分钟。';
        }
        if (t.atTime.isNotEmpty && atTimeNext(t.atTime, DateTime.now()) == null) {
          return '时刻写成 HH:MM 的样子，比如 08:30。';
        }
    }
    if (t.action == TriggerActionKind.prompt && t.actionText.isEmpty) {
      return '要让模型跑一句话，就把那句话写进 action_text。';
    }
    if (t.action == TriggerActionKind.notify && t.actionText.isEmpty) {
      return '发通知这一类要写正文，不然通知上只有名字。';
    }
    return '';
  }

  static TriggerKind _kindOf(String name, TriggerKind fallback) {
    for (final TriggerKind k in TriggerKind.values) {
      if (k.name == name.trim()) return k;
    }
    return fallback;
  }

  static TriggerActionKind _actionOf(String name, TriggerActionKind fallback) {
    for (final TriggerActionKind a in TriggerActionKind.values) {
      if (a.name == name.trim()) return a;
    }
    return fallback;
  }
}

/// `trigger_delete`：删掉一条触发器。
class TriggerDeleteTool extends Tool {
  TriggerDeleteTool(this.triggers);

  final TriggerStore triggers;

  @override
  String get name => 'trigger_delete';

  @override
  String get description => '删掉一条触发器，连同它的运行记录。按 id 或名字找。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'id': <String, Object?>{'type': 'string', 'description': '要删的那一条的 id'},
          'name': <String, Object?>{'type': 'string', 'description': '或者写名字，撞上多条就报出来'},
        },
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.write;

  @override
  bool get alwaysAsk => true;

  @override
  String summarize(Map<String, Object?> args) =>
      '删掉触发器 ${readString(args, 'name', fallback: readString(args, 'id'))}';

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final Object? found = _find(triggers, args);
    if (found is String) return ToolOutcome.failure(found);
    final Trigger t = found as Trigger;
    await triggers.remove(t.id);
    return ToolOutcome.success(stdout: '删掉了触发器「${t.title}」。');
  }
}

/// 按 id 或名字找一条触发器。找不到或者撞上多条都返回一句说明。
Object _find(TriggerStore store, Map<String, Object?> args) {
  final String id = readString(args, 'id').trim();
  if (id.isNotEmpty) {
    final Trigger? t = store.byId(id);
    return t ?? '没有 id 是 $id 的触发器。先用 trigger_list 看一眼。';
  }
  final String name = readString(args, 'name').trim();
  if (name.isEmpty) return '要写 id 或者名字。先用 trigger_list 看一眼。';
  final List<Trigger> hits =
      store.all.where((Trigger t) => t.name == name || t.title == name).toList();
  if (hits.isEmpty) return '没有叫「$name」的触发器。';
  if (hits.length > 1) {
    return '叫「$name」的有 ${hits.length} 条，用 id 指一条：'
        '${hits.map((Trigger t) => t.id).join('、')}。';
  }
  return hits.first;
}

String _conditionOf(Trigger t) => switch (t.kind) {
      TriggerKind.phone => '手机状态「${t.intent}」',
      TriggerKind.message => '通知碰上「${t.intent}」',
      TriggerKind.schedule => t.atTime.isEmpty ? '每 ${t.everyMinutes} 分钟' : '每天 ${t.atTime}',
    };

String _clip(String text, int max) =>
    text.length <= max ? text : '${text.substring(0, max)}…';

String _stamp(DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
}
