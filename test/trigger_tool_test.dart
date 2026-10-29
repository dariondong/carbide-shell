import 'dart:io';

import 'package:carbide_shell/core/models.dart';
import 'package:carbide_shell/core/triggers.dart';
import 'package:carbide_shell/data/triggers.dart';
import 'package:carbide_shell/tools/trigger_tool.dart';
import 'package:flutter_test/flutter_test.dart';

const ToolContext _ctx = ToolContext(workspace: '/tmp', desktop: true);

void main() {
  late Directory dir;
  late TriggerStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('carbide_trigger_tool');
    store = TriggerStore(File('${dir.path}/triggers.json'));
    await store.load();
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('模型建一条触发器，清单里马上能看到', () async {
    final ToolOutcome out = await TriggerSaveTool(store).run(<String, Object?>{
      'name': '到家提醒',
      'kind': 'phone',
      'intent': '到家了在充电',
      'action': 'notify',
      'action_text': '到家了',
    }, _ctx);

    expect(out.ok, isTrue);
    expect(store.all.length, 1);
    final Trigger t = store.all.single;
    expect(t.title, '到家提醒');
    expect(t.kind, TriggerKind.phone);
    expect(t.intent, '到家了在充电');
    // 新建的默认就开着，不然它一辈子不会跑。
    expect(t.enabled, isTrue);
    expect(t.nextAt, isNotNull);

    final ToolOutcome list = await TriggerListTool(store).run(<String, Object?>{}, _ctx);
    expect(list.ok, isTrue);
    expect(list.stdout.contains('到家提醒'), isTrue);
    expect(list.stdout.contains('手机状态'), isTrue);
  });

  test('定时那一种写时刻，没写时刻写间隔', () async {
    final ToolOutcome every = await TriggerSaveTool(store).run(<String, Object?>{
      'name': '半小时看一眼',
      'kind': 'schedule',
      'every_minutes': 30,
      'action': 'prompt',
      'action_text': '看看磁盘',
    }, _ctx);
    expect(every.ok, isTrue);
    expect(store.all.single.everyMinutes, 30);

    final ToolOutcome at = await TriggerSaveTool(store).run(<String, Object?>{
      'name': '早上八点',
      'kind': 'schedule',
      'at_time': '08:30',
      'action': 'prompt',
      'action_text': '说一句早安',
    }, _ctx);
    expect(at.ok, isTrue);
    expect(store.byId('t2')!.atTime, '08:30');

    final ToolOutcome bad = await TriggerSaveTool(store).run(<String, Object?>{
      'name': '写错时刻',
      'kind': 'schedule',
      'at_time': '八点半',
      'action': 'prompt',
      'action_text': 'x',
    }, _ctx);
    expect(bad.ok, isFalse);
  });

  test('条件或动作空着就不收', () async {
    final ToolOutcome noIntent = await TriggerSaveTool(store)
        .run(<String, Object?>{'name': '空条件', 'kind': 'phone'}, _ctx);
    expect(noIntent.ok, isFalse);
    expect(noIntent.error.contains('看什么'), isTrue);

    final ToolOutcome noAction = await TriggerSaveTool(store).run(<String, Object?>{
      'name': '没写做什么',
      'kind': 'message',
      'intent': '外卖',
      'action': 'prompt',
    }, _ctx);
    expect(noAction.ok, isFalse);
    expect(store.all, isEmpty);
  });

  test('给同样的名字就是改那一条，其它项照旧', () async {
    await TriggerSaveTool(store).run(<String, Object?>{
      'name': '到家提醒',
      'kind': 'phone',
      'intent': '到家了在充电',
      'action': 'notify',
      'action_text': '到家了',
    }, _ctx);
    final String id = store.all.single.id;

    final ToolOutcome out = await TriggerSaveTool(store)
        .run(<String, Object?>{'name': '到家提醒', 'action_text': '已经到家了'}, _ctx);
    expect(out.ok, isTrue);
    expect(store.all.length, 1);
    expect(store.all.single.id, id);
    expect(store.all.single.intent, '到家了在充电');
    expect(store.all.single.actionText, '已经到家了');
  });

  test('给 id 改别的名字那一条', () async {
    await TriggerSaveTool(store).run(<String, Object?>{
      'name': 'a',
      'kind': 'message',
      'intent': '外卖',
      'action': 'notify',
      'action_text': '外卖到了',
    }, _ctx);
    await TriggerSaveTool(store).run(<String, Object?>{
      'name': 'b',
      'kind': 'message',
      'intent': '快递',
      'action': 'notify',
      'action_text': '快递到了',
    }, _ctx);
    final String first = store.all.first.id;
    await TriggerSaveTool(store)
        .run(<String, Object?>{'id': first, 'enabled': false}, _ctx);
    expect(store.byId(first)!.enabled, isFalse);
    expect(store.byId(first)!.nextAt, isNull);
    expect(store.all.length, 2);
  });

  test('删掉一条；找不到就说清楚', () async {
    await TriggerSaveTool(store).run(<String, Object?>{
      'name': '空的',
      'kind': 'message',
      'intent': '外卖',
      'action': 'notify',
      'action_text': '外卖到了',
    }, _ctx);
    final ToolOutcome out = await TriggerDeleteTool(store)
        .run(<String, Object?>{'name': '空的'}, _ctx);
    expect(out.ok, isTrue);
    expect(store.all, isEmpty);

    final ToolOutcome miss = await TriggerDeleteTool(store)
        .run(<String, Object?>{'name': '空的'}, _ctx);
    expect(miss.ok, isFalse);
  });

  test('改触发器、删触发器都要先问一句', () {
    final TriggerSaveTool save = TriggerSaveTool(store);
    final TriggerDeleteTool remove = TriggerDeleteTool(store);
    expect(save.alwaysAsk, isTrue);
    expect(remove.alwaysAsk, isTrue);
    expect(TriggerListTool(store).alwaysAsk, isFalse);
  });
}
