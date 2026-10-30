import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/agent.dart';
import '../core/conversation.dart';
import '../core/models.dart';
import '../core/schedule.dart';
import '../core/triggers.dart';
import '../services.dart';
import 'device.dart';
import 'foreground.dart';
import 'llm_settings.dart';

/// 触发器清单：一个 JSON 文件，和主机、设置放在一起。
class TriggerStore {
  TriggerStore(this.file);

  final File file;
  final List<Trigger> _items = <Trigger>[];

  List<Trigger> get all => List<Trigger>.unmodifiable(_items);

  Trigger? byId(String id) {
    for (final Trigger t in _items) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> load() async {
    _items.clear();
    if (!file.existsSync()) return;
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      final Object? list = decoded['triggers'];
      if (list is List) {
        for (final Object? raw in list) {
          if (raw is! Map) continue;
          final Trigger t = Trigger.fromJson(Map<String, Object?>.from(raw));
          if (t.id.isEmpty) continue;
          _items.add(t);
        }
      }
    } catch (_) {
      // 文件坏了就从空清单开始，不挡住应用起来。
    }
  }

  Future<void> save() async {
    file.parent.createSync(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'triggers': _items.map((Trigger t) => t.toJson()).toList(),
    }));
  }

  Future<void> upsert(Trigger trigger) async {
    final int at = _items.indexWhere((Trigger t) => t.id == trigger.id);
    if (at >= 0) {
      _items[at] = trigger;
    } else {
      _items.add(trigger);
    }
    await save();
  }

  Future<void> remove(String id) async {
    _items.removeWhere((Trigger t) => t.id == id);
    await save();
  }

  String nextId() {
    int n = _items.length + 1;
    while (_items.any((Trigger t) => t.id == 't$n')) {
      n += 1;
    }
    return 't$n';
  }
}

/// 触发器跑起来时没有人守在旁边。要确认的那一档按这条触发器自己的设置走：
/// 放行就照做，只读就一律拒绝。会把机器弄坏的那一档在策略层就拦下了，两边都一样。
class _ReadOnlyApprover implements Approver {
  const _ReadOnlyApprover();

  @override
  Future<bool> confirm(ApprovalRequest request) async => false;
}

class _AutoApprover implements Approver {
  const _AutoApprover();

  @override
  Future<bool> confirm(ApprovalRequest request) async => true;
}

const String kTriggerRunNote = '''
这一次是触发器自动跑起来的，没有人在旁边回答。
只做读的事：需要确认的操作会被拒绝，被拒了就在结论里说一句。
结论写短一点，第一行就是结果。''';

const String kTriggerRunNoteWrite = '''
这一次是触发器自动跑起来的，没有人在旁边回答，需要确认的操作已经放行。
危险的那一类（删根、关机、格式化）仍然会被拒绝，被拒了就在结论里说一句。
结论写短一点，第一行就是结果。''';

/// 触发器每半分钟看一次：到点的、碰上关键词的、手机状态符合的，各走各自的路。
class TriggerRunner {
  TriggerRunner({
    required this.services,
    required this.store,
    this.onChanged,
  });

  final AppServices services;
  final TriggerStore store;

  void Function()? onChanged;

  static const Duration tickEvery = Duration(seconds: 30);

  Timer? _timer;
  bool _busy = false;

  /// 手机状态判断最多花这么久，超了这次就算没触发。
  static const Duration judgeTimeout = Duration(seconds: 60);

  /// 一个动作（可能是一轮模型对话）最多跑这么久。
  static const Duration actTimeout = Duration(minutes: 5);

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(tickEvery, (_) => unawaited(tick()));
    unawaited(tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> tick({DateTime? now}) async {
    if (_busy) return;
    _busy = true;
    bool changed = false;
    try {
      final DateTime at = now ?? DateTime.now();
      for (final Trigger t in store.all.toList()) {
        if (!t.enabled) continue;
        final DateTime? due = t.nextAt;
        if (due == null) {
          t.nextAt = nextDueAt(t, at);
          changed = true;
          await store.save();
          continue;
        }
        if (at.isBefore(due)) continue;
        // 先把下一次排好：这一次跑砸了也不会在同一分钟反复跑。
        t.nextAt = nextDueAt(t, at.add(const Duration(seconds: 1)));
        await store.save();
        changed = true;
        await _fire(t, at);
      }
    } finally {
      _busy = false;
      if (changed) onChanged?.call();
    }
  }

  /// 现在就试一次，不管到没到点。
  Future<String> runNow(Trigger t) async {
    await _fire(t, DateTime.now());
    return t.runs.isEmpty ? '没跑成' : t.runs.first.note;
  }

  /// 等在确认的那一条：批准了就把当时那句话真的跑掉。
  Future<void> approve(Trigger t) async {
    final TriggerRun? pending = t.runs.isEmpty ? null : t.runs.first;
    if (pending == null || pending.status != TriggerRunStatus.waiting) return;
    t.runs.removeAt(0);
    await _act(t, DateTime.now(), reason: pending.note);
  }

  /// 不批：把那条待确认的记成没触发。
  Future<void> dismiss(Trigger t) async {
    final TriggerRun? pending = t.runs.isEmpty ? null : t.runs.first;
    if (pending == null || pending.status != TriggerRunStatus.waiting) return;
    t.runs.removeAt(0);
    t.addRun(TriggerRun(
      at: DateTime.now(),
      status: TriggerRunStatus.skipped,
      note: '没批准，没有执行。${pending.note}',
    ));
    await store.save();
    onChanged?.call();
  }

  bool get busy => _busy;

  Future<void> _fire(Trigger t, DateTime at) async {
    // 先记下上一次看的时间再挪：消息通知要按「上一回看到现在」这一段比对，
    // 先挪就等于拿一个空区间去比，永远碰不上。
    final DateTime? previous = t.lastAt;
    t.lastAt = at;
    switch (t.kind) {
      case TriggerKind.schedule:
        await _act(t, at, reason: '到点了');
      case TriggerKind.message:
        await _checkMessage(t, at, previous: previous);
      case TriggerKind.phone:
        await _checkPhone(t, at);
    }
  }

  /// 消息通知：上一次看到现在，有没有碰上关键词的那一条。
  Future<void> _checkMessage(Trigger t, DateTime at, {DateTime? previous}) async {
    if (t.keywords.isEmpty) {
      await _skip(t, '还没写关键词');
      return;
    }
    final DeviceApi device = services.device;
    if (!device.supported) {
      await _skip(t, '这台机器上读不到通知');
      return;
    }
    try {
      // 先问一句系统给没给「通知使用权」：没给就不是「没碰上关键词」。
      final bool granted = await device.has(DevicePerm.notification);
      if (!granted) {
        await _skip(t, '系统还没给「通知使用权」，去系统设置里给这一项再回来看');
        return;
      }
    } on DeviceError catch (e) {
      await _skip(t, e.message);
      return;
    }
    final DateTime since = messageSince(at, previous);
    try {
      final List<DeviceNotification> list =
          await device.notifications(limit: 100, minutes: 720);
      final List<DeviceNotification> fresh = list
          .where((DeviceNotification n) => n.at != null && !n.at!.isBefore(since))
          .toList();
      // 分开数两种：碰上关键词的，和确实冲着我来的。
      // 写清楚了「我是谁」时，只有后一种才算触发。
      int keywordHits = 0;
      for (final DeviceNotification n in fresh) {
        if (!keywordHit(t, n.title, n.text)) continue;
        keywordHits++;
        if (!messageMatches(t, n.title, n.text)) continue;
        final String what = n.title.trim().isEmpty ? n.text.trim() : n.title.trim();
        await _act(t, at,
            reason: '${n.app.isEmpty ? '通知' : n.app}「${_clip(what, 40)}」'
                '${targetReason(t, n.title, n.text)}');
        return;
      }
      await _skip(
        t,
        fresh.isEmpty
            ? '这一段时间（从 ${_clock(since)} 起）一条通知都没收到'
            : '看了 ${fresh.length} 条通知（从 ${_clock(since)} 起），'
                '${keywordHits == 0 ? '没碰上关键词' : '碰上 ${keywordHits} 条但都不是冲着我说的'}',
      );
    } on DeviceError catch (e) {
      await _skip(t, e.message);
    } catch (e) {
      await _skip(t, '读通知失败：$e');
    }
  }

  /// 记录里写的时刻：`10-30 05:12`。
  static String _clock(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
  }

  /// 手机状态：把允许看的那几项交给模型，让它说触发还是不触发。
  Future<void> _checkPhone(Trigger t, DateTime at) async {
    if (t.intent.trim().isEmpty) {
      await _skip(t, '还没写要看什么状态');
      return;
    }
    final DeviceApi device = services.device;
    if (!device.supported) {
      await _skip(t, '这台机器上读不到手机状态');
      return;
    }
    PhoneSignals signals;
    try {
      signals = await device.phoneState();
    } on DeviceError catch (e) {
      await _skip(t, e.message);
      return;
    } catch (e) {
      await _skip(t, '读状态失败：$e');
      return;
    }
    final SettingsLlmProvider llm = SettingsLlmProvider(services.settings, services.secrets);
    PhoneJudge judge;
    try {
      final LlmReply reply = await llm
          .chat(
            system: kPhoneJudgeSystem,
            messages: <LlmMessage>[LlmMessage.user(phoneJudgePrompt(t, signals, at))],
            tools: const <ToolSpec>[],
          )
          .timeout(judgeTimeout);
      judge = parseJudge(reply.text);
    } catch (e) {
      await _skip(t, '模型没判断成：$e');
      return;
    }
    if (!judge.match) {
      await _skip(t, judge.text);
      return;
    }
    if (t.needsConfirm) {
      t.addRun(TriggerRun(at: at, status: TriggerRunStatus.waiting, note: judge.text));
      await store.save();
      onChanged?.call();
      await ForegroundTask.alert(
        t.title,
        '条件满足了，等你点一下才动手。\n${judge.text}',
        slot: _slotOf(t.id),
      );
      return;
    }
    await _act(t, at, reason: judge.text);
  }

  /// 打开一个应用：名字写错了就把像的那几个写进记录，下次好改。
  Future<void> _launch(Trigger t, DateTime at, {required String reason}) async {
    final String query = t.actionText.trim();
    if (query.isEmpty) {
      await _skip(t, '还没写要打开哪个应用');
      return;
    }
    final DeviceApi device = services.device;
    if (!device.supported) {
      await _skip(t, '这台机器上打不开应用');
      return;
    }
    try {
      final OpenAppResult r = await device.openApp(query);
      if (!r.ok) {
        final String near = r.near.isEmpty ? '' : '，像的有：${r.near.join('、')}';
        t.addRun(TriggerRun(
          at: at,
          status: TriggerRunStatus.failed,
          note: '没打开「$query」${r.why.isEmpty ? '' : '：${r.why}'}$near',
        ));
        await store.save();
        onChanged?.call();
        return;
      }
      t.addRun(TriggerRun(
        at: at,
        status: TriggerRunStatus.fired,
        note: '打开了 ${r.app}${reason.isEmpty ? '' : '（$reason）'}',
      ));
      await store.save();
      onChanged?.call();
      await ForegroundTask.alert(t.title, '打开了 ${r.app}', slot: _slotOf(t.id));
    } on DeviceError catch (e) {
      await _skip(t, e.message);
    }
  }

  Future<void> _skip(Trigger t, String note) async {
    t.addRun(TriggerRun(at: DateTime.now(), status: TriggerRunStatus.skipped, note: note));
    await store.save();
    onChanged?.call();
  }

  /// 真的动手：发一条通知、打开一个应用，或者让模型跑一句。
  Future<void> _act(Trigger t, DateTime at, {required String reason}) async {
    if (t.action == TriggerActionKind.openApp) {
      await _launch(t, at, reason: reason);
      return;
    }
    if (t.action == TriggerActionKind.notify) {
      final String head = t.actionText.trim();
      await ForegroundTask.alert(
        t.title,
        head.isEmpty ? reason : '$head\n$reason',
        slot: _slotOf(t.id),
      );
      t.addRun(TriggerRun(at: at, status: TriggerRunStatus.fired, note: reason));
      await store.save();
      onChanged?.call();
      return;
    }
    final String prompt = t.actionText.trim();
    if (prompt.isEmpty) {
      await _skip(t, '还没写要模型做什么');
      return;
    }
    String answer = '';
    String note = '';
    try {
      final Conversation scope = Conversation(
        id: 'trigger-${t.id}',
        title: t.title,
        hostId: '',
      );
      final AgentSession session = await services.sessionFor(scope);
      session.loop.approver =
          t.allowWrite ? const _AutoApprover() : const _ReadOnlyApprover();
      session.loop.extraSystem = t.allowWrite ? kTriggerRunNoteWrite : kTriggerRunNote;
      answer = await session.loop.send('$prompt\n\n（触发原因：$reason）').timeout(actTimeout);
      note = summaryLine(answer);
    } catch (e) {
      final String text = '$e'.replaceFirst('Exception: ', '');
      t.addRun(TriggerRun(at: at, status: TriggerRunStatus.failed, note: '跑失败了：$text'));
      await store.save();
      onChanged?.call();
      await ForegroundTask.alert(t.title, '触发器跑失败了：$text', slot: _slotOf(t.id));
      return;
    }
    final bool failed = answer.startsWith('模型请求失败');
    t.addRun(TriggerRun(
      at: at,
      status: failed ? TriggerRunStatus.failed : TriggerRunStatus.fired,
      note: note.isEmpty ? reason : note,
    ));
    await store.save();
    onChanged?.call();
    await ForegroundTask.alert(
      t.title,
      note.isEmpty ? reason : note,
      slot: _slotOf(t.id),
    );
  }

  /// 一条触发器占一个通知位，别把别的通知盖掉；第 0 位留给资源监听。
  static int _slotOf(String id) {
    int sum = 0;
    for (final int unit in id.codeUnits) {
      sum = (sum * 31 + unit) & 0x7fffffff;
    }
    return 1 + sum % 31;
  }

  static String _clip(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';
}
