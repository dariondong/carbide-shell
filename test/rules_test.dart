import 'package:carbide_shell/core/monitor.dart';
import 'package:carbide_shell/core/rules.dart';
import 'package:carbide_shell/core/schedule.dart';
import 'package:flutter_test/flutter_test.dart';

HostMetrics metrics({
  double cpu = 20,
  int memTotal = 8000000,
  int memAvail = 6000000,
  int diskTotal = 100000,
  int diskUsed = 50000,
  int swapTotal = 0,
  int swapFree = 0,
  double load = 0.5,
}) =>
    HostMetrics(
      at: DateTime(2026, 10, 24, 3),
      cpuPercent: cpu,
      memTotalKb: memTotal,
      memAvailKb: memAvail,
      diskTotalKb: diskTotal,
      diskUsedKb: diskUsed,
      swapTotalKb: swapTotal,
      swapFreeKb: swapFree,
      load1: load,
    );

void main() {
  group('读一条条件', () {
    test('英文写法', () {
      final TaskRule? r = parseRule('disk>90');
      expect(r, isNotNull);
      expect(r!.metric, RuleMetric.disk);
      expect(r.op, RuleOp.gt);
      expect(r.value, 90);
    });

    test('中文写法、带空格和百分号', () {
      final TaskRule? r = parseRule(' 磁盘 >= 90% ');
      expect(r, isNotNull);
      expect(r!.metric, RuleMetric.disk);
      expect(r.op, RuleOp.ge);
      expect(r.value, 90);
    });

    test('负载小于', () {
      final TaskRule? r = parseRule('load<=4');
      expect(r!.metric, RuleMetric.load);
      expect(r.op, RuleOp.le);
    });

    test('认不出的给 null', () {
      expect(parseRule('磁盘 90'), isNull);
      expect(parseRule('温度>50'), isNull);
      expect(parseRule(''), isNull);
    });

    test('写法念回来一样', () {
      expect(parseRule('disk>90')!.text, '磁盘 > 90');
      expect(parseRule('load>=4')!.text, '负载 ≥ 4');
    });
  });

  group('判一次', () {
    test('全要满足：一条没过就不跑', () {
      final RuleCheck c = checkRules(
        <TaskRule>[parseRule('disk>90')!, parseRule('load>4')!],
        metrics: metrics(diskUsed: 95000, load: 1),
      );
      expect(c.met, isFalse);
      expect(c.text.contains('负载 1（要 负载 > 4）'), isTrue);
    });

    test('全要满足：都过了就带上读数', () {
      final RuleCheck c = checkRules(
        <TaskRule>[parseRule('disk>90')!, parseRule('load>0.2')!],
        metrics: metrics(diskUsed: 95000, load: 0.4),
      );
      expect(c.met, isTrue);
      expect(c.text, '磁盘 95%、负载 0.4');
    });

    test('满足一条就够', () {
      final RuleCheck c = checkRules(
        <TaskRule>[parseRule('disk>90')!, parseRule('load>4')!],
        all: false,
        metrics: metrics(diskUsed: 95000, load: 0.3),
      );
      expect(c.met, isTrue);
    });

    test('读不到的那一项算没过', () {
      final RuleCheck c = checkRules(
        <TaskRule>[parseRule('swap>10')!],
        metrics: metrics(swapTotal: 0),
      );
      expect(c.met, isFalse);
      expect(c.text.contains('交换读不到'), isTrue);
    });

    test('没有条件就是通过', () {
      expect(checkRules(<TaskRule>[], metrics: metrics()).met, isTrue);
    });
  });

  group('条件写进任务', () {
    test('存下来再读回来还是那几条', () {
      final ScheduledTask t = ScheduledTask(
        id: 'k1',
        title: '磁盘',
        prompt: '清一下',
        hostId: 'h1',
        condition: RuleNode.group(logic: RuleLogic.any, children: <RuleNode>[
          RuleNode.rule(parseRule('disk>90')!),
          RuleNode.rule(parseRule('load>2')!),
        ]),
        gateRetryMinutes: 15,
        gateWindowMinutes: 120,
      );
      final ScheduledTask back = ScheduledTask.fromJson(t.toJson());
      expect(back.condition!.leaves, 2);
      expect(back.condition!.children.first.rule!.metric, RuleMetric.disk);
      expect(back.condition!.logic, RuleLogic.any);
      expect(back.gateRetryStep, 15);
      expect(back.gateWindowStep, 120);
      expect(back.conditionText, '磁盘 > 90 或 负载 > 2');
    });

    test('旧条目里平的条件读成一棵树', () {
      final ScheduledTask back = ScheduledTask.fromJson(<String, Object?>{
        'id': 'k4',
        'title': '旧',
        'prompt': '看看',
        'rules': <Object?>[
          <String, Object?>{'metric': 'disk', 'op': 'gt', 'value': 90},
          <String, Object?>{'metric': 'cpu', 'op': 'gt', 'value': 80},
        ],
        'rulesAll': false,
      });
      expect(back.gated, isTrue);
      expect(back.condition!.logic, RuleLogic.any);
      expect(back.conditionText, '磁盘 > 90 或 CPU > 80');
    });

    test('没有条件的旧条目照旧读得出来', () {
      final ScheduledTask back = ScheduledTask.fromJson(<String, Object?>{
        'id': 'k2',
        'title': '旧',
        'prompt': '看看',
        'kind': 'daily',
      });
      expect(back.condition, isNull);
      expect(back.gated, isFalse);
      expect(back.gateWindowStep, 60);
    });

    test('改完重排就把等条件的状态清掉', () {
      final ScheduledTask t = ScheduledTask(
        id: 'k3',
        title: 'x',
        prompt: 'y',
        condition: RuleNode.rule(parseRule('disk>90')!),
        nextAt: DateTime(2026, 10, 24, 3),
        gateAt: DateTime(2026, 10, 24, 3, 5),
      );
      t.reschedule(DateTime(2026, 10, 24, 4));
      expect(t.gateAt, isNull);
    });

    test('一串带括号的条件读成一棵树', () {
      final RuleNode? node = parseCondition('disk>90 且 (cpu>80 或 memory>=85)');
      expect(node, isNotNull);
      expect(node!.logic, RuleLogic.all);
      expect(node.children.length, 2);
      expect(node.children[1].logic, RuleLogic.any);
      expect(node.depth, 3);
      expect(node.leaves, 3);
      expect(conditionTextOf(node), '磁盘 > 90 且 （CPU > 80 或 内存 ≥ 85）');
    });

    test('and / or 也认，且比或紧一层', () {
      final RuleNode? node = parseCondition('disk>90 and cpu>80 or load>4');
      expect(node, isNotNull);
      expect(node!.logic, RuleLogic.any);
      expect(node.children.first.logic, RuleLogic.all);
    });

    test('读不出来的条件给 null', () {
      expect(parseCondition(''), isNull);
      expect(parseCondition('磁盘快满了'), isNull);
      expect(parseCondition('disk>90 且'), isNull);
      expect(parseCondition('(disk>90'), isNull);
    });

    test('一棵树按自己的连接词判', () {
      final RuleNode node = parseCondition('disk>90 且 (cpu>80 或 memory>=85)')!;
      // 磁盘没过，整条就不过。
      final RuleCheck low = checkCondition(
          node, metrics: metrics(cpu: 95, memAvail: 800000));
      expect(low.met, isFalse);
      expect(low.misses.any((String m) => m.contains('磁盘')), isTrue);
      // 磁盘过了，括号里 CPU 也过。
      expect(
        checkCondition(node, metrics: metrics(cpu: 95, diskUsed: 95000)).met,
        isTrue,
      );
      // 磁盘过了，括号里两条都不过。
      expect(
        checkCondition(node, metrics: metrics(cpu: 10, memAvail: 7900000, diskUsed: 95000))
            .met,
        isFalse,
      );
    });

    test('树上只装一条时收成那一条', () {
      final RuleNode node = RuleNode.group(children: <RuleNode>[
        RuleNode.rule(parseRule('disk>90')!),
      ]);
      expect(node.collapse().isGroup, isFalse);
      final RuleNode deep = parseCondition('(disk>90)')!;
      expect(conditionTextOf(deep.collapse()), '磁盘 > 90');
    });

    test('树存下来读回来形状不变', () {
      final RuleNode node = parseCondition('disk>90 且 (cpu>80 或 load>4)')!;
      final RuleNode? back = RuleNode.fromJson(node.toJson());
      expect(back, isNotNull);
      expect(conditionTextOf(back), conditionTextOf(node));
      expect(back!.leaves, node.leaves);
    });

    test('跳过的那一轮记得住原因', () {
      final TaskRun run = TaskRun(
        at: DateTime(2026, 10, 24, 3),
        skipped: true,
        gate: '磁盘 78%',
        note: '条件没满足，这一轮没有跑：磁盘 78%',
      );
      final TaskRun back = TaskRun.fromJson(run.toJson());
      expect(back.skipped, isTrue);
      expect(back.gate, '磁盘 78%');
    });
  });
}
