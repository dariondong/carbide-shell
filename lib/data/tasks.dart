import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/agent.dart';
import '../core/conversation.dart';
import '../core/schedule.dart';
import '../services.dart';
import 'foreground.dart';

/// 定时任务清单，一个 JSON 文件，和主机、设置放在一起。
class TaskStore {
  TaskStore(this.file);

  final File file;
  final List<ScheduledTask> _items = <ScheduledTask>[];

  List<ScheduledTask> get all => List<ScheduledTask>.unmodifiable(_items);

  ScheduledTask? byId(String id) {
    for (final ScheduledTask t in _items) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> load() async {
    _items.clear();
    if (!file.existsSync()) return;
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        final Object? list = decoded['tasks'];
        if (list is List) {
          for (final Object? raw in list) {
            if (raw is! Map) continue;
            final ScheduledTask t = ScheduledTask.fromJson(Map<String, Object?>.from(raw));
            if (t.id.isEmpty || t.prompt.trim().isEmpty) continue;
            _items.add(t);
          }
        }
      }
    } catch (_) {
      // 文件坏了就从空清单开始，不要让整个应用起不来。
    }
  }

  Future<void> save() async {
    file.parent.createSync(recursive: true);
    final String text = const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'tasks': _items.map((ScheduledTask t) => t.toJson()).toList(),
    });
    await file.writeAsString(text);
  }

  Future<void> upsert(ScheduledTask task) async {
    final int index = _items.indexWhere((ScheduledTask t) => t.id == task.id);
    if (index >= 0) {
      _items[index] = task;
    } else {
      _items.add(task);
    }
    await save();
  }

  Future<void> remove(String id) async {
    _items.removeWhere((ScheduledTask t) => t.id == id);
    await save();
  }

  static String newId() => 'k${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
}

/// 定时任务没人能回答它的追问，所以除危险命令之外一律照做。
/// 危险命令在策略层就被拦下了，这里不重复判断。
class _AutoApprove implements Approver {
  const _AutoApprove();

  @override
  Future<bool> confirm(ApprovalRequest request) async => true;
}

/// 每次自动执行时拼在系统提示后面的那一段。
const String kTaskRunNote = '''
这一次是定时任务的自动执行，没有人在旁边回答。
需要用户确认、需要输入或者要等很久的操作直接跳过，并在结论里说清楚跳过了什么。
结论写短一点，第一行就是结果。''';

/// 应用的计时器：每 20 秒看一次有没有到点的任务，到点就开跑。
///
/// 跑在应用自己的进程里，所以系统把应用彻底清掉时不会触发；错过三小时以内的
/// 会在下次打开时补跑一次，再久就跳过并记一笔。
class TaskScheduler {
  TaskScheduler({
    required this.services,
    required this.tasks,
    this.onChanged,
  });

  final AppServices services;
  final TaskStore tasks;

  /// 清单有变化（跑了、失败了、排到下一次了）就通知界面重画。
  void Function()? onChanged;

  static const Duration tickEvery = Duration(seconds: 20);

  Timer? _timer;
  bool _busy = false;
  final Set<String> _running = <String>{};
  DateTime _lastNotice = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastNoticeText = '';

  /// 正在跑的任务 id，界面上转个圈。
  Set<String> get runningIds => Set<String>.unmodifiable(_running);

  bool isRunning(String id) => _running.contains(id);

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(tickEvery, (_) => tick());
    unawaited(tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 检查一轮。一个任务跑着的时候不叠加，等它跑完再说。
  Future<void> tick({DateTime? now}) async {
    if (_busy) return;
    _busy = true;
    try {
      final DateTime at = now ?? DateTime.now();
      bool changed = false;
      for (final ScheduledTask task in tasks.all.toList()) {
        if (!task.enabled) continue;
        if (task.nextAt == null) {
          task.scheduleFrom(at);
          changed = true;
          continue;
        }
        final DueAction action = dueAction(task, at);
        if (action == DueAction.none) continue;
        final DateTime scheduled = task.nextAt!;
        // 先把下一次排好再跑：跑的时候进程被杀，重启也不会把同一次再跑一遍。
        if (task.kind == ScheduleKind.once) {
          task.enabled = false;
          task.nextAt = null;
        } else {
          task.scheduleFrom(at);
        }
        await tasks.save();
        changed = true;

        if (action == DueAction.skip) {
          task.addRun(TaskRun(
            at: scheduled,
            missed: true,
            note: '错过了 ${untilText(scheduled, at).replaceFirst('已过 ', '')}，没有补跑',
          ));
          await tasks.save();
          onChanged?.call();
          continue;
        }
        await _run(task, scheduled, late: action == DueAction.runLate);
      }
      if (changed) onChanged?.call();
    } finally {
      _busy = false;
    }
  }

  /// 界面上点「跑一次」。不改下一次的时刻。
  Future<void> runNow(ScheduledTask task) async {
    if (_running.contains(task.id)) return;
    await _run(task, DateTime.now(), late: false);
  }

  Future<void> _run(ScheduledTask task, DateTime scheduled, {required bool late}) async {
    _running.add(task.id);
    onChanged?.call();
    unawaited(ForegroundTask.begin('定时任务 · ${task.title}'));
    // 每次开跑都从干净的通知节流开始，上一次跑剩下的那句话不带到这一次。
    _lastNotice = DateTime.fromMillisecondsSinceEpoch(0);
    _lastNoticeText = '';

    String answer = '';
    int steps = 0;
    int tokens = 0;
    bool ok = false;
    String note = '';
    try {
      // 任务的记忆跟着它的范围走：单机任务和单机对话共用一份记忆。
      final Conversation scope = Conversation(
        id: 'task-${task.id}',
        title: task.title,
        hostId: task.hostId,
      );
      final AgentSession session = await services.sessionFor(scope);
      final AgentLoop loop = session.loop;
      loop.approver = const _AutoApprove();
      loop.maxSteps = services.settings.value.maxSteps;
      final String extra = services.settings.value.extraPrompt.trim();
      loop.extraSystem = extra.isEmpty ? kTaskRunNote : '$extra\n$kTaskRunNote';
      loop.onChanged = () => _noteProgress(task, loop);

      answer = await loop.send(task.prompt);
      steps = loop.step;
      tokens = loop.tokens;
      ok = !answer.startsWith('模型请求失败');
      note = ok ? summaryLine(answer) : answer.trim();
    } catch (e) {
      note = '跑失败了：$e';
    } finally {
      _running.remove(task.id);
      task.addRun(TaskRun(
        at: scheduled,
        ok: ok,
        note: note,
        answer: answer.length > 4000 ? '${answer.substring(0, 4000)}…' : answer,
        steps: steps,
        tokens: tokens,
        late: late,
      ));
      await tasks.save();
      final String done = ok ? '跑完了' : '失败了';
      unawaited(ForegroundTask.visible
          ? ForegroundTask.end()
          : ForegroundTask.finish('${task.title} · $done'));
      onChanged?.call();
    }
  }

  /// 通知上那句进度：走到第几步、在等什么。1.2 秒一次，文字没变就不重发。
  void _noteProgress(ScheduledTask task, AgentLoop loop) {
    final DateTime now = DateTime.now();
    if (now.difference(_lastNotice).inMilliseconds < 1200) return;
    _lastNotice = now;
    final String where = switch (loop.phase) {
      AgentPhase.thinking => '等模型回话',
      AgentPhase.acting => '执行命令',
      AgentPhase.waiting => '等确认',
      AgentPhase.idle => '收尾',
    };
    final String text = '${task.title} · 第 ${loop.step}/${loop.maxSteps} 步 · $where';
    if (text == _lastNoticeText) return;
    _lastNoticeText = text;
    unawaited(ForegroundTask.update(text));
  }
}
