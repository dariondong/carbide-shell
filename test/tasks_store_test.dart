import 'dart:io';

import 'package:carbide_shell/core/schedule.dart';
import 'package:carbide_shell/data/tasks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('carbide_tasks');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('存进去再读出来，删掉就真没了', () async {
    final File file = File('${dir.path}/tasks.json');
    final TaskStore store = TaskStore(file);
    await store.load();
    expect(store.all, isEmpty);

    final ScheduledTask task = ScheduledTask(
      id: 'k1',
      title: '磁盘体检',
      prompt: '看看磁盘还剩多少，超过 85% 就说一声',
      hostId: 'h1',
      kind: ScheduleKind.weekly,
      weekdays: <int>[3],
      minuteOfDay: 540,
    );
    task.addRun(TaskRun(at: DateTime(2026, 10, 24, 12, 0), ok: true, note: '剩 13% 余量'));
    await store.upsert(task);

    final TaskStore again = TaskStore(file);
    await again.load();
    expect(again.all.length, 1);
    expect(again.byId('k1')!.title, '磁盘体检');
    expect(again.byId('k1')!.when, '每周三 09:00');
    expect(again.all.single.runs.single.note, '剩 13% 余量');

    await again.remove('k1');
    final TaskStore third = TaskStore(file);
    await third.load();
    expect(third.all, isEmpty);
  });

  test('同名任务改一份不会多出一条', () async {
    final TaskStore store = TaskStore(File('${dir.path}/tasks.json'));
    final ScheduledTask task = ScheduledTask(id: 'k2', title: '巡检', prompt: '看看负载');
    await store.upsert(task);
    task.title = '巡检（改）';
    await store.upsert(task);
    expect(store.all.length, 1);
    expect(store.all.single.title, '巡检（改）');
  });

  test('文件坏了就从空清单开始', () async {
    File('${dir.path}/tasks.json').writeAsStringSync('{这不是 json');
    final TaskStore store = TaskStore(File('${dir.path}/tasks.json'));
    await store.load();
    expect(store.all, isEmpty);
  });

  test('没有指令的任务不算数', () async {
    final File file = File('${dir.path}/tasks.json');
    file.writeAsStringSync(
      '{"tasks":[{"id":"k3","title":"空","prompt":"  "},{"id":"k4","title":"好","prompt":"看看磁盘"}]}',
    );
    final TaskStore store = TaskStore(file);
    await store.load();
    expect(store.all.length, 1);
    expect(store.all.single.id, 'k4');
  });
}
