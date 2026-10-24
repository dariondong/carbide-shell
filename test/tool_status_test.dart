import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:carbide_shell/core/models.dart';
import 'package:carbide_shell/core/schedule.dart';
import 'package:carbide_shell/core/watch.dart';
import 'package:carbide_shell/data/hosts.dart';
import 'package:carbide_shell/data/tasks.dart';
import 'package:carbide_shell/data/watch.dart';
import 'package:carbide_shell/tools/status_tools.dart';

Directory _temp() => Directory.systemTemp.createTempSync('carbide_tools_');

const ToolContext _ctx = ToolContext(workspace: '/tmp', desktop: true);

void main() {
  late Directory dir;

  setUp(() {
    dir = _temp();
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('host_list', () {
    test('列出名字、地址、登录方式和指纹状态', () async {
      final HostStore hosts = HostStore(File('${dir.path}/hosts.json'));
      await hosts.upsert(HostEntry(
          id: 'h1', name: 'web-01', host: '10.0.0.5', port: 22, user: 'root'));
      final ToolOutcome out = await HostListTool(hosts: hosts).run(<String, Object?>{}, _ctx);
      expect(out.ok, isTrue);
      expect(out.stdout, contains('web-01'));
      expect(out.stdout, contains('10.0.0.5:22'));
      expect(out.stdout, contains('密码登录'));
      expect(out.stdout, contains('指纹待确认'));
    });

    test('单主机对话只看得到自己那一台', () async {
      final HostStore hosts = HostStore(File('${dir.path}/hosts.json'));
      await hosts.upsert(HostEntry(id: 'h1', name: 'web-01', host: '10.0.0.5'));
      await hosts.upsert(HostEntry(id: 'h2', name: 'db-01', host: '10.0.0.6'));
      final ToolOutcome out =
          await HostListTool(hosts: hosts, onlyHostId: 'h2').run(<String, Object?>{}, _ctx);
      expect(out.stdout, contains('db-01'));
      expect(out.stdout, isNot(contains('web-01')));
    });
  });

  group('task_list 与 task_control', () {
    test('列出下次时间、开关和所属主机', () async {
      final TaskStore tasks = TaskStore(File('${dir.path}/tasks.json'));
      final ScheduledTask t = ScheduledTask(
          id: 'k1', title: '磁盘体检', prompt: '看看磁盘', kind: ScheduleKind.daily,
          minuteOfDay: 180)
        ..reschedule(DateTime(2026, 10, 26, 1, 0));
      await tasks.upsert(t);
      final ToolOutcome out = await TaskListTool(tasks: tasks, hosts: HostStore(File('${dir.path}/h.json')))
          .run(<String, Object?>{}, _ctx);
      expect(out.stdout, contains('磁盘体检'));
      expect(out.stdout, contains('全部主机'));
      expect(out.stdout, contains('开着'));
      expect(out.stdout, contains('k1'));
    });

    test('停掉一条，再恢复', () async {
      final TaskStore tasks = TaskStore(File('${dir.path}/tasks.json'));
      final ScheduledTask t = ScheduledTask(
          id: 'k1', title: '磁盘体检', prompt: '看看磁盘', kind: ScheduleKind.daily,
          minuteOfDay: 180)
        ..reschedule(DateTime.now());
      await tasks.upsert(t);
      final TaskControlTool tool = TaskControlTool(tasks);

      ToolOutcome out = await tool.run(
          <String, Object?>{'title': '磁盘体检', 'op': 'pause'}, _ctx);
      expect(out.ok, isTrue);
      expect(tasks.all.single.enabled, isFalse);
      expect(tasks.all.single.nextAt, isNull);

      out = await tool.run(<String, Object?>{'title': '磁盘体检', 'op': 'resume'}, _ctx);
      expect(out.ok, isTrue);
      expect(tasks.all.single.enabled, isTrue);
      expect(tasks.all.single.nextAt, isNotNull);
    });

    test('删掉一条就真的没了', () async {
      final TaskStore tasks = TaskStore(File('${dir.path}/tasks.json'));
      await tasks.upsert(ScheduledTask(
          id: 'k1', title: '磁盘体检', prompt: '看看磁盘', kind: ScheduleKind.daily,
          minuteOfDay: 180));
      final ToolOutcome out = await TaskControlTool(tasks)
          .run(<String, Object?>{'title': '磁盘体检', 'op': 'remove'}, _ctx);
      expect(out.ok, isTrue);
      expect(tasks.all, isEmpty);
    });

    test('名字对不上就把现有的报出来', () async {
      final TaskStore tasks = TaskStore(File('${dir.path}/tasks.json'));
      await tasks.upsert(ScheduledTask(
          id: 'k1', title: '磁盘体检', prompt: '看看磁盘', kind: ScheduleKind.daily,
          minuteOfDay: 180));
      final ToolOutcome out = await TaskControlTool(tasks).run(
          <String, Object?>{'title': '内存体检', 'op': 'pause'}, _ctx);
      expect(out.ok, isFalse);
      expect(out.error, contains('磁盘体检'));
    });
  });

  group('watch_list 与 watch_control', () {
    test('列出条件与最近读数', () async {
      final WatchStore watches = WatchStore(File('${dir.path}/watches.json'));
      final HostStore hosts = HostStore(File('${dir.path}/hosts.json'));
      await hosts.upsert(HostEntry(id: 'h1', name: 'web-01', host: '10.0.0.5'));
      final WatchTask w = WatchTask(
          id: 'w1', title: 'web-01 磁盘', hostId: 'h1',
          metric: WatchMetric.disk, threshold: 90);
      w.addHit(WatchHit(at: DateTime(2026, 10, 26, 3, 0), value: 94, fired: true));
      await watches.upsert(w);
      final ToolOutcome out =
          await WatchListTool(watches: watches, hosts: hosts).run(<String, Object?>{}, _ctx);
      expect(out.stdout, contains('web-01 磁盘'));
      expect(out.stdout, contains('磁盘 > 90%'));
      expect(out.stdout, contains('94%'));
      expect(out.stdout, contains('已提醒'));
    });

    test('停掉一条监听', () async {
      final WatchStore watches = WatchStore(File('${dir.path}/watches.json'));
      await watches.upsert(WatchTask(id: 'w1', title: '磁盘', hostId: 'h1'));
      final ToolOutcome out = await WatchControlTool(watches)
          .run(<String, Object?>{'title': '磁盘', 'op': 'pause'}, _ctx);
      expect(out.ok, isTrue);
      expect(watches.all.single.enabled, isFalse);
      expect(watches.all.single.nextAt, isNull);
    });
  });
}
