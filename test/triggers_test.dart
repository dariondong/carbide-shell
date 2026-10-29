import 'package:carbide_shell/core/triggers.dart';
import 'package:carbide_shell/data/device.dart';
import 'package:flutter_test/flutter_test.dart';

const PhoneSignals _phone = PhoneSignals(
  battery: 62,
  charging: true,
  screenOn: false,
  locked: true,
  network: 'wifi',
  headset: true,
  ringer: 'silent',
  dnd: true,
  music: false,
);

void main() {
  test('关键字拆得开，也认中英文逗号', () {
    final Trigger t = Trigger(id: 't1', intent: '备份, 完成；disk full 空间');
    expect(t.keywords, <String>['备份', '完成', 'disk', 'full', '空间']);
    expect(messageMatches(t, '备份完成', ''), isTrue);
    expect(messageMatches(t, '', 'disk usage 报警'), isTrue);
    expect(messageMatches(t, '无关', 'nothing'), isFalse);
    final Trigger empty = Trigger(id: 't2');
    expect(messageMatches(empty, '随便', '什么'), isFalse);
  });

  test('允许看哪几项信号', () {
    final Trigger t = Trigger(id: 't1', signals: <String>['battery', 'charging']);
    expect(t.allowsSignal('battery'), isTrue);
    expect(t.allowsSignal('locked'), isFalse);
    final String text = signalsForPrompt(t, _phone);
    expect(text, contains('62%'));
    expect(text, contains('在充电'));
    expect(text, isNot(contains('锁屏')));
    // 一项都不选 = 全都允许。
    final Trigger all = Trigger(id: 't2');
    expect(all.allowsSignal('locked'), isTrue);
    expect(signalsForPrompt(all, _phone), contains('锁'));
  });

  test('模型那一行 JSON 读得回来，读不像就当不触发', () {
    final PhoneJudge yes = parseJudge(
        '好的\n{"match": true, "reason": "在充电且锁屏", "confidence": 0.86}');
    expect(yes.match, isTrue);
    expect(yes.reason, '在充电且锁屏');
    expect(yes.confidence, closeTo(0.86, 1e-9));
    expect(yes.text, contains('86%'));
    final PhoneJudge no = parseJudge('我不确定');
    expect(no.match, isFalse);
    final PhoneJudge clamp = parseJudge('{"match": true, "reason": "x", "confidence": 5}');
    expect(clamp.confidence, 1);
  });

  test('下一次什么时候看它', () {
    final DateTime now = DateTime(2026, 10, 28, 8, 0);
    final Trigger every = Trigger(id: 't1', kind: TriggerKind.phone, everyMinutes: 15);
    expect(nextDueAt(every, now), now.add(const Duration(minutes: 15)));
    final Trigger daily = Trigger(id: 't2', kind: TriggerKind.schedule, atTime: '08:30');
    expect(nextDueAt(daily, now), DateTime(2026, 10, 28, 8, 30));
    expect(nextDueAt(daily, DateTime(2026, 10, 28, 9, 0)), DateTime(2026, 10, 29, 8, 30));
    final Trigger broken =
        Trigger(id: 't3', kind: TriggerKind.schedule, atTime: '25:00', everyMinutes: 30);
    expect(nextDueAt(broken, now), now.add(const Duration(minutes: 30)));
  });

  test('发通知不用再问，让模型跑才问', () {
    final Trigger notify =
        Trigger(id: 't1', action: TriggerActionKind.notify, confirm: true);
    expect(notify.needsConfirm, isFalse);
    final Trigger prompt =
        Trigger(id: 't2', action: TriggerActionKind.prompt, confirm: true);
    expect(prompt.needsConfirm, isTrue);
  });

  test('存下来再读回来', () {
    final Trigger t = Trigger(
      id: 't9',
      name: '插电',
      kind: TriggerKind.phone,
      enabled: true,
      intent: '插上电并且锁屏',
      signals: <String>['battery', 'charging'],
      everyMinutes: 5,
      action: TriggerActionKind.prompt,
      actionText: '看一眼磁盘',
      confirm: true,
      nextAt: DateTime(2026, 10, 28, 9, 0),
    );
    t.addRun(TriggerRun(
        at: DateTime(2026, 10, 28, 8, 55), status: TriggerRunStatus.skipped, note: '没插电'));
    final Trigger back = Trigger.fromJson(t.toJson());
    expect(back.name, '插电');
    expect(back.kind, TriggerKind.phone);
    expect(back.intent, '插上电并且锁屏');
    expect(back.signals, <String>['battery', 'charging']);
    expect(back.action, TriggerActionKind.prompt);
    expect(back.confirm, isTrue);
    expect(back.nextAt, DateTime(2026, 10, 28, 9, 0));
    expect(back.runs.length, 1);
    expect(back.runs.first.status, TriggerRunStatus.skipped);
  });

  test('运行记录最多留二十条', () {
    final Trigger t = Trigger(id: 't1');
    for (int i = 0; i < 30; i += 1) {
      t.addRun(TriggerRun(at: DateTime(2026, 10, 28, 8, i), status: TriggerRunStatus.fired));
    }
    expect(t.runs.length, Trigger.maxRuns);
    expect(t.runs.first.at.minute, 29);
  });
}
