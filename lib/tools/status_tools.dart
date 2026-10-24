import '../core/models.dart';
import '../core/schedule.dart';
import '../core/tools.dart';
import '../core/watch.dart';
import '../data/hosts.dart';
import '../data/tasks.dart';
import '../data/watch.dart';

/// 这几件是「看得见自己做过什么」的那一半：主机、定时任务、资源监听都能查，
/// 也能停、能删。查是只读，停和删要过审批。

/// 主机清单。单主机对话只看得到那一台。
class HostListTool extends Tool {
  HostListTool({required this.hosts, this.onlyHostId = ''});

  final HostStore hosts;
  final String onlyHostId;

  @override
  String get name => 'host_list';

  @override
  String get description => '列出这个对话能用的主机：名字、地址、端口、账号、登录方式，以及指纹确认了没有。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.read;

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final List<HostEntry> list = onlyHostId.isEmpty
        ? hosts.hosts
        : hosts.hosts.where((HostEntry h) => h.id == onlyHostId).toList();
    if (list.isEmpty) {
      return const ToolOutcome.success(stdout: '这个对话一台主机都没有。要让用户先去主机页加一台。');
    }
    final StringBuffer b = StringBuffer('${list.length} 台\n');
    for (final HostEntry h in list) {
      b.writeln('- ${h.name}：${h.address}:${h.port}，账号 ${h.user}，'
          '${h.auth == 'key' ? '私钥' : '密码'}登录，'
          '${h.trusted ? '指纹已记' : '指纹待确认'}');
    }
    return ToolOutcome.success(stdout: b.toString().trimRight());
  }
}

/// 定时任务清单。
class TaskListTool extends Tool {
  TaskListTool({required this.tasks, required this.hosts, this.onlyHostId = ''});

  final TaskStore tasks;
  final HostStore hosts;
  final String onlyHostId;

  @override
  String get name => 'task_list';

  @override
  String get description => '列出已经排好的定时任务：什么时候跑、管哪台、下次什么时候、开着还是停了、上次跑成什么样。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.read;

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final List<ScheduledTask> list = tasks.all
        .where((ScheduledTask t) => onlyHostId.isEmpty || t.hostId == onlyHostId || t.hostId.isEmpty)
        .toList();
    if (list.isEmpty) return const ToolOutcome.success(stdout: '还没有定时任务。');
    final StringBuffer b = StringBuffer('${list.length} 条定时任务\n');
    for (final ScheduledTask t in list) {
      final String host = t.hostId.isEmpty
          ? '全部主机'
          : (hosts.byId(t.hostId)?.name ?? '主机已删除');
      final String next = t.nextAt == null ? '没有下一次' : stampText(t.nextAt!);
      final String last = t.runs.isEmpty
          ? '还没跑过'
          : (t.runs.first.ok ? '上次成功' : '上次失败');
      b.writeln('- ${t.title}：${t.when}，$host，'
          '${t.enabled ? '开着' : '已停'}，下次 $next，$last'
          '（id ${t.id}）');
    }
    return ToolOutcome.success(stdout: b.toString().trimRight());
  }
}

/// 资源监听清单。
class WatchListTool extends Tool {
  WatchListTool({required this.watches, required this.hosts, this.onlyHostId = ''});

  final WatchStore watches;
  final HostStore hosts;
  final String onlyHostId;

  @override
  String get name => 'watch_list';

  @override
  String get description => '列出已经排好的监听：看哪台的哪一项、阈值多少、多久读一次、最近读到什么。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.read;

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final List<WatchTask> list = watches.all
        .where((WatchTask w) => onlyHostId.isEmpty || w.hostId == onlyHostId)
        .toList();
    if (list.isEmpty) return const ToolOutcome.success(stdout: '还没有资源监听。');
    final StringBuffer b = StringBuffer('${list.length} 条监听\n');
    for (final WatchTask w in list) {
      final String host = hosts.byId(w.hostId)?.name ?? '主机已删除';
      final WatchHit? hit = w.lastHit;
      final String last = hit == null
          ? '还没读过'
          : (hit.error.isNotEmpty
              ? '${hit.stamp} 读不到：${hit.error}'
              : '${hit.stamp} ${w.valueText(hit.value ?? 0)}${hit.fired ? ' 已提醒' : ''}');
      b.writeln('- ${w.title}：$host，${w.when}，'
          '${w.enabled ? '开着' : '已停'}，$last（id ${w.id}）');
    }
    return ToolOutcome.success(stdout: b.toString().trimRight());
  }
}

/// 停掉、恢复、删掉一条定时任务。
class TaskControlTool extends Tool {
  TaskControlTool(this.tasks);

  final TaskStore tasks;

  @override
  String get name => 'task_control';

  @override
  String get description => '停掉、恢复或删掉一条定时任务。按名字找，找不到就报出来。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'title': <String, Object?>{'type': 'string', 'description': '任务名字，task_list 里看到的那一个'},
          'op': <String, Object?>{
            'type': 'string',
            'enum': <String>['pause', 'resume', 'remove'],
          },
        },
        'required': <String>['title', 'op'],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.write;

  @override
  String summarize(Map<String, Object?> args) {
    final String op = readString(args, 'op');
    final String word = op == 'remove' ? '删掉' : (op == 'pause' ? '停掉' : '恢复');
    return '$word定时任务 ${readString(args, 'title')}';
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String op = readString(args, 'op');
    final Object? found = _findTask(tasks, readString(args, 'title'));
    if (found is String) return ToolOutcome.failure(found);
    final ScheduledTask task = found as ScheduledTask;
    if (op == 'remove') {
      await tasks.remove(task.id);
      return ToolOutcome.success(stdout: '删掉了定时任务「${task.title}」。');
    }
    task.enabled = op == 'resume';
    if (task.enabled) {
      task.reschedule(DateTime.now());
    } else {
      task.nextAt = null;
    }
    await tasks.upsert(task);
    return ToolOutcome.success(
      stdout: '「${task.title}」${task.enabled ? '恢复' : '停'}了。'
          '${task.nextAt == null ? '' : '下次 ${stampText(task.nextAt!)}。'}',
    );
  }
}

/// 停掉、恢复、删掉一条资源监听。
class WatchControlTool extends Tool {
  WatchControlTool(this.watches);

  final WatchStore watches;

  @override
  String get name => 'watch_control';

  @override
  String get description => '停掉、恢复或删掉一条资源监听。按名字找，找不到就报出来。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'title': <String, Object?>{'type': 'string', 'description': '监听名字，watch_list 里看到的那一个'},
          'op': <String, Object?>{
            'type': 'string',
            'enum': <String>['pause', 'resume', 'remove'],
          },
        },
        'required': <String>['title', 'op'],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.write;

  @override
  String summarize(Map<String, Object?> args) {
    final String op = readString(args, 'op');
    final String word = op == 'remove' ? '删掉' : (op == 'pause' ? '停掉' : '恢复');
    return '$word监听 ${readString(args, 'title')}';
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String op = readString(args, 'op');
    final Object? found = _findWatch(watches, readString(args, 'title'));
    if (found is String) return ToolOutcome.failure(found);
    final WatchTask watch = found as WatchTask;
    if (op == 'remove') {
      await watches.remove(watch.id);
      return ToolOutcome.success(stdout: '删掉了监听「${watch.title}」。');
    }
    watch.enabled = op == 'resume';
    if (watch.enabled) {
      watch.scheduleFrom(DateTime.now());
    } else {
      watch.nextAt = null;
    }
    await watches.upsert(watch);
    return ToolOutcome.success(stdout: '「${watch.title}」${watch.enabled ? '恢复' : '停'}了。');
  }
}

/// 按名字找一条任务：先认全名，再认唯一的一段。找不到或撞上多条都返回一句说明。
Object _findTask(TaskStore tasks, String name) {
  final String want = name.trim();
  if (want.isEmpty) return '名字是空的。先用 task_list 看一眼有哪些。';
  final List<ScheduledTask> exact =
      tasks.all.where((ScheduledTask t) => t.title == want || t.id == want).toList();
  if (exact.length == 1) return exact.first;
  final List<ScheduledTask> loose = tasks.all
      .where((ScheduledTask t) => t.title.contains(want))
      .toList();
  if (loose.length == 1) return loose.first;
  if (loose.isEmpty) {
    final String names = tasks.all.map((ScheduledTask t) => t.title).join('、');
    return names.isEmpty ? '还没有定时任务。' : '没有叫「$want」的任务。现在有：$names';
  }
  return '「$want」对上了 ${loose.length} 条：'
      '${loose.map((ScheduledTask t) => t.title).join('、')}。说全名。';
}

Object _findWatch(WatchStore watches, String name) {
  final String want = name.trim();
  if (want.isEmpty) return '名字是空的。先用 watch_list 看一眼有哪些。';
  final List<WatchTask> exact =
      watches.all.where((WatchTask w) => w.title == want || w.id == want).toList();
  if (exact.length == 1) return exact.first;
  final List<WatchTask> loose =
      watches.all.where((WatchTask w) => w.title.contains(want)).toList();
  if (loose.length == 1) return loose.first;
  if (loose.isEmpty) {
    final String names = watches.all.map((WatchTask w) => w.title).join('、');
    return names.isEmpty ? '还没有资源监听。' : '没有叫「$want」的监听。现在有：$names';
  }
  return '「$want」对上了 ${loose.length} 条：'
      '${loose.map((WatchTask w) => w.title).join('、')}。说全名。';
}
