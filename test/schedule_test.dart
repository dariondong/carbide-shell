import 'package:carbide_shell/core/schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String fmt(DateTime? d) => d == null ? 'null' : stampText(d, now: DateTime(2026, 10, 24));

  final DateTime sat = DateTime(2026, 10, 24, 12, 0);

  group('排时刻', () {
    test('2026-10-24 是周六', () {
      expect(sat.weekday, 6);
    });

    test('每天 03:00', () {
      final ScheduledTask t = ScheduledTask(
        id: 'a',
        title: 't',
        prompt: 'p',
        kind: ScheduleKind.daily,
        minuteOfDay: 180,
      );
      expect(fmt(t.nextRunAfter(sat)), '10-25 03:00');
      expect(fmt(t.nextRunAfter(DateTime(2026, 10, 24, 1, 0))), '10-24 03:00');
      expect(t.when, '每天 03:00');
    });

    test('每周一、周四 08:30', () {
      final ScheduledTask t = ScheduledTask(
        id: 'b',
        title: 't',
        prompt: 'p',
        kind: ScheduleKind.weekly,
        weekdays: <int>[1, 4],
        minuteOfDay: 510,
      );
      expect(fmt(t.nextRunAfter(sat)), '10-26 08:30');
      expect(fmt(t.nextRunAfter(DateTime(2026, 10, 26, 9, 0))), '10-29 08:30');
      expect(t.when, '每周一、四 08:30');
    });

    test('按间隔排，锚点是创建时刻', () {
      final ScheduledTask t = ScheduledTask(
        id: 'c',
        title: 't',
        prompt: 'p',
        kind: ScheduleKind.interval,
        intervalMinutes: 60,
        createdAt: DateTime(2026, 10, 24, 0, 0),
      );
      expect(fmt(t.nextRunAfter(sat)), '10-24 13:00');
      expect(fmt(t.nextRunAfter(DateTime(2026, 10, 24, 0, 30))), '10-24 01:00');
      expect(fmt(t.nextRunAfter(DateTime(2026, 10, 24, 0, 0))), '10-24 01:00');
      expect(t.when, '每 1 小时');
      expect(
        ScheduledTask(id: 'd', title: 't', prompt: 'p', kind: ScheduleKind.interval, intervalMinutes: 90)
            .when,
        '每 1 小时 30 分',
      );
      expect(
        ScheduledTask(id: 'e', title: 't', prompt: 'p', kind: ScheduleKind.interval, intervalMinutes: 1)
            .intervalStep,
        5,
      );
    });

    test('只跑一次', () {
      final ScheduledTask t = ScheduledTask(
        id: 'f',
        title: 't',
        prompt: 'p',
        kind: ScheduleKind.once,
        onceAt: DateTime(2026, 10, 26, 9, 0),
      );
      expect(fmt(t.nextRunAfter(sat)), '10-26 09:00');
      expect(fmt(t.nextRunAfter(DateTime(2026, 10, 27))), 'null');
      expect(t.when, '一次 10-26 09:00');
    });

    test('定在过去的一次性任务编辑后废掉', () {
      final ScheduledTask t = ScheduledTask(id: 'i', title: 't', prompt: 'p', kind: ScheduleKind.once)
        ..onceAt = DateTime(2026, 1, 1, 9, 0);
      t.reschedule(sat);
      expect(t.enabled, isFalse);
      expect(t.nextAt, isNull);
    });
  });

  group('到点判定', () {
    ScheduledTask due() => ScheduledTask(id: 'g', title: 't', prompt: 'p')
      ..nextAt = DateTime(2026, 10, 24, 12, 0);

    test('没到点', () {
      expect(dueAction(due(), DateTime(2026, 10, 24, 11, 59)), DueAction.none);
    });

    test('准点与两分钟内都算准点', () {
      expect(dueAction(due(), DateTime(2026, 10, 24, 12, 0)), DueAction.run);
      expect(dueAction(due(), DateTime(2026, 10, 24, 12, 2)), DueAction.run);
    });

    test('过十分钟算补跑，过四小时不补', () {
      expect(dueAction(due(), DateTime(2026, 10, 24, 12, 10)), DueAction.runLate);
      expect(dueAction(due(), DateTime(2026, 10, 24, 16, 0)), DueAction.skip);
    });

    test('停用或没有下一次都不动', () {
      final ScheduledTask off = due()..enabled = false;
      expect(dueAction(off, DateTime(2026, 10, 24, 12, 5)), DueAction.none);
      final ScheduledTask none = due()..nextAt = null;
      expect(dueAction(none, DateTime(2026, 10, 24, 12, 5)), DueAction.none);
    });
  });

  group('文案与存盘', () {
    final DateTime now = DateTime(2026, 10, 24, 12, 0);

    test('还有多久', () {
      expect(untilText(DateTime(2026, 10, 24, 12, 3), now), '还有 3 分钟');
      expect(untilText(DateTime(2026, 10, 24, 10, 0), now), '已过 2 小时');
      expect(untilText(DateTime(2026, 10, 25, 15, 0), now), '还有 1 天 3 小时');
      expect(untilText(null, now), '');
    });

    test('时刻文案', () {
      expect(clockText(15 * 60 + 5), '15:05');
      expect(clockText(9999), '23:59');
      expect(summaryLine('\n\n磁盘用了 87%\n细节…'), '磁盘用了 87%');
      expect(summaryLine('   '), '');
    });

    test('存盘往返', () {
      final ScheduledTask t = ScheduledTask(
        id: 'b',
        title: '体检',
        prompt: '看看磁盘',
        hostId: 'h1',
        kind: ScheduleKind.weekly,
        weekdays: <int>[1, 4],
        minuteOfDay: 510,
      );
      t.addRun(TaskRun(at: now, ok: true, note: '磁盘 87%', steps: 3, tokens: 1200));
      final ScheduledTask back = ScheduledTask.fromJson(t.toJson());
      expect(back.when, '每周一、四 08:30');
      expect(back.hostId, 'h1');
      expect(back.runs.single.note, '磁盘 87%');
      expect(back.runs.single.steps, 3);
      expect(ScheduledTask.fromJson(ScheduledTask(id: 'z', title: 't', prompt: 'p').toJson()).when,
          '每天 03:00');
    });

    test('运行记录只留最近 kMaxRuns 条', () {
      final ScheduledTask t = ScheduledTask(id: 'h', title: 't', prompt: 'p');
      for (int i = 0; i < 30; i += 1) {
        t.addRun(TaskRun(at: DateTime(2026, 10, 24, 0, i % 60), ok: true, note: '$i'));
      }
      expect(t.runs.length, kMaxRuns);
      expect(t.runs.first.note, '29');
    });
  });
}
