import 'package:test/test.dart';

import 'package:carbide_shell/core/watch.dart';

const String _lastOut = '''
root     pts/0        203.0.113.9      Sun Oct 25 21:14:03 2026   still logged in
root     pts/1        198.51.100.7     Sat Oct 24 09:02:11 2026 - Sat Oct 24 09:30:00 2026  (00:27)
reboot   system boot  6.8.0-45-generic Sat Oct 24 08:00:01 2026 - Sun Oct 26 10:00:00 2026  (2+02:00)
root     tty1                          Fri Oct 23 07:00:00 2026 - Fri Oct 23 07:05:00 2026  (00:05)

wtmp begins Fri Oct 03 00:00:00 2026
''';

const String _lastbOut = '''
root     ssh:notty    45.9.148.20      Sun Oct 26 03:11:07 2026 - Sun Oct 26 03:11:07 2026  (00:00)
admin    ssh:notty    45.9.148.20      Sun Oct 26 03:10:59 2026 - Sun Oct 26 03:10:59 2026  (00:00)
root     ssh:notty    45.9.148.20      Sun Oct 26 03:09:41 2026 - Sun Oct 26 03:09:41 2026  (00:00)

btmp begins Sun Oct 26 03:00:00 2026
''';

void main() {
  group('读 last 的输出', () {
    test('来源、时间、控制台登录都读对', () {
      final List<LoginEvent> events = parseLastLog(_lastOut);
      expect(events.length, 3, reason: 'reboot 与 wtmp begins 要跳过');
      expect(events[0].user, 'root');
      expect(events[0].host, '203.0.113.9');
      expect(events[0].remote, isTrue);
      expect(events[0].at, DateTime(2026, 10, 25, 21, 14, 3));
      expect(events[1].host, '198.51.100.7');
      expect(events[1].at, DateTime(2026, 10, 24, 9, 2, 11));
    });

    test('没有来源那一格的控制台登录 host 为空，不算远程', () {
      final LoginEvent console = parseLastLog(_lastOut)[2];
      expect(console.user, 'root');
      expect(console.host, '');
      expect(console.remote, isFalse);
    });

    test('空输出不报错，只给空清单', () {
      expect(parseLastLog(''), isEmpty);
      expect(parseLastLog('\n\n'), isEmpty);
    });
  });

  group('读 lastb 的输出', () {
    test('三次失败登录都在', () {
      final List<LoginEvent> events = parseLastLog(_lastbOut);
      expect(events.length, 3);
      expect(events.map((LoginEvent e) => e.host).toSet(), <String>{'45.9.148.20'});
      expect(events.first.at, DateTime(2026, 10, 26, 3, 11, 7));
    });
  });

  group('什么时候提醒', () {
    test('三种条件的说明文字', () {
      final WatchTask metric = WatchTask(
        id: 'a',
        title: 'a',
        hostId: 'h',
        metric: WatchMetric.disk,
        threshold: 90,
      );
      expect(metric.when, '每 5 分钟看一次 · 磁盘 > 90%');

      final WatchTask fails = WatchTask(
        id: 'b',
        title: 'b',
        hostId: 'h',
        kind: WatchKind.loginFail,
        threshold: 10,
        windowMinutes: 10,
        intervalMinutes: 60,
      );
      expect(fails.when, '每 1 小时看一次 · 10 分钟内失败登录 ≥ 10 次');

      final WatchTask fresh = WatchTask(
        id: 'c',
        title: 'c',
        hostId: 'h',
        kind: WatchKind.loginNew,
      );
      expect(fresh.when, '每 5 分钟看一次 · 出现没见过的 IP 登录');
    });

    test('值的写法按种类分开', () {
      final WatchTask metric = WatchTask(
          id: 'a', title: 'a', hostId: 'h', metric: WatchMetric.load);
      expect(metric.valueText(3.14159), '3.14');
      final WatchTask disk =
          WatchTask(id: 'b', title: 'b', hostId: 'h', metric: WatchMetric.disk);
      expect(disk.valueText(91.6), '92%');
      final WatchTask fails = WatchTask(
          id: 'c', title: 'c', hostId: 'h', kind: WatchKind.loginFail);
      expect(fails.valueText(12), '12 次');
      final WatchTask fresh = WatchTask(
          id: 'd', title: 'd', hostId: 'h', kind: WatchKind.loginNew);
      expect(fresh.valueText(2), '2 个新 IP');
    });

    test('通知那句带主机名和阈值', () {
      final WatchTask disk = WatchTask(
          id: 'a', title: 'a', hostId: 'h', metric: WatchMetric.disk, threshold: 90);
      expect(disk.alertBody('web-01', 94), 'web-01 磁盘 94%（超过 90%）');
      final WatchTask fails = WatchTask(
          id: 'b', title: 'b', hostId: 'h', kind: WatchKind.loginFail, threshold: 10);
      expect(fails.alertBody('web-01', 17), 'web-01 10 分钟内失败登录 17 次');
      final WatchTask fresh = WatchTask(
          id: 'c', title: 'c', hostId: 'h', kind: WatchKind.loginNew);
      expect(fresh.alertBody('web-01', 1, extra: '45.9.148.20'),
          'web-01 有没见过的来源登录：45.9.148.20');
    });

    test('超过与低于两个方向', () {
      final WatchTask high = WatchTask(
          id: 'a', title: 'a', hostId: 'h', metric: WatchMetric.disk, threshold: 90);
      expect(high.passes(90.5), isTrue);
      expect(high.passes(90), isFalse);
      final WatchTask low = WatchTask(
          id: 'b',
          title: 'b',
          hostId: 'h',
          metric: WatchMetric.disk,
          above: false,
          threshold: 10);
      expect(low.passes(9), isTrue);
      expect(low.passes(11), isFalse);
    });
  });

  group('新 IP 登录怎么算', () {
    test('第一次只记下来，不报', () {
      final WatchTask watch = WatchTask(
          id: 'c', title: 'c', hostId: 'h', kind: WatchKind.loginNew);
      expect(watch.knownIps, isEmpty);
      final List<LoginEvent> events = parseLastLog(_lastOut);
      watch.takeNewHosts(events);
      expect(watch.knownIps, containsAll(<String>['203.0.113.9', '198.51.100.7']));
    });

    test('见过的来源不再报，新的那个才报', () {
      final WatchTask watch = WatchTask(
          id: 'c', title: 'c', hostId: 'h', kind: WatchKind.loginNew);
      watch.knownIps.addAll(<String>['203.0.113.9', '198.51.100.7']);
      final List<LoginEvent> events = parseLastLog(_lastOut);
      expect(watch.takeNewHosts(events), isEmpty);

      final List<LoginEvent> more = parseLastLog(
          'root     pts/2        192.0.2.44       Mon Oct 26 08:00:00 2026   still logged in\n');
      expect(watch.takeNewHosts(more), <String>['192.0.2.44']);
      expect(watch.takeNewHosts(more), isEmpty, reason: '第二次同一个来源不该再报');
    });

    test('控制台登录不算来源', () {
      final WatchTask watch = WatchTask(
          id: 'c', title: 'c', hostId: 'h', kind: WatchKind.loginNew);
      watch.knownIps.add('203.0.113.9');
      final List<LoginEvent> events = parseLastLog(
          'root     tty1                          Fri Oct 23 07:00:00 2026 - Fri Oct 23 07:05:00 2026  (00:05)\n');
      expect(watch.takeNewHosts(events), isEmpty);
    });
  });

  test('存盘再读回来，种类、窗口、见过的来源都在', () {
    final WatchTask watch = WatchTask(
      id: 'w1',
      title: 'web-01 失败登录',
      hostId: 'h1',
      kind: WatchKind.loginFail,
      threshold: 8,
      windowMinutes: 30,
      intervalMinutes: 15,
      cooldownMinutes: 120,
      knownIps: <String>{'192.0.2.44'},
    );
    watch.addHit(WatchHit(at: DateTime(2026, 10, 26, 3, 11), value: 12, fired: true));
    final WatchTask back = WatchTask.fromJson(watch.toJson());
    expect(back.kind, WatchKind.loginFail);
    expect(back.threshold, 8);
    expect(back.windowMinutes, 30);
    expect(back.intervalMinutes, 15);
    expect(back.cooldownMinutes, 120);
    expect(back.knownIps, <String>{'192.0.2.44'});
    expect(back.hits.length, 1);
    expect(back.hits.first.fired, isTrue);
    expect(back.hits.first.value, 12);
  });
}
