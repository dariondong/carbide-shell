import 'package:carbide_shell/core/models.dart';
import 'package:carbide_shell/core/plan.dart';
import 'package:carbide_shell/tools/plan_tool.dart';
import 'package:flutter_test/flutter_test.dart';

const ToolContext _ctx = ToolContext(workspace: '/tmp', desktop: true);

void main() {
  test('计划存下来再读回来，状态一个不差', () {
    final WorkPlan plan = WorkPlan(goal: '清磁盘', steps: <PlanStep>[
      const PlanStep(title: '看用量', state: PlanState.done),
      const PlanStep(title: '删旧日志', state: PlanState.doing),
      const PlanStep(title: '复查', state: PlanState.todo),
    ]);
    final WorkPlan? back = WorkPlan.fromJson(plan.toJson());
    expect(back, isNotNull);
    expect(back!.goal, '清磁盘');
    expect(back.steps.length, 3);
    expect(back.steps[1].state, PlanState.doing);
    expect(back.doneCount, 1);
    expect(back.finished, isFalse);
    expect(back.headline, '3 步 · 做完 1 步');
  });

  test('空计划读回来是 null，界面上不会留半张卡', () {
    expect(WorkPlan.fromJson(<String, Object?>{'steps': <Object?>[]}), isNull);
    expect(WorkPlan.fromJson(null), isNull);
  });

  test('模型写中文的状态也认', () {
    expect(planStateOf('完成'), PlanState.done);
    expect(planStateOf('进行中'), PlanState.doing);
    expect(planStateOf('随便'), PlanState.todo);
  });

  test('工具写一遍计划，交给对话的那一份和回来的一致', () async {
    WorkPlan? kept;
    final PlanTool tool = PlanTool(onChanged: (WorkPlan p) => kept = p);
    final ToolOutcome out = await tool.run(<String, Object?>{
      'goal': '清磁盘',
      'steps': <Object?>[
        <String, Object?>{'title': '看用量', 'state': 'done'},
        <String, Object?>{
          'title': '删旧日志',
          'state': 'doing',
        },
        '复查',
      ],
    }, _ctx);
    expect(out.ok, isTrue);
    expect(kept, isNotNull);
    expect(kept!.steps.length, 3);
    expect(kept!.steps.first.state, PlanState.done);
    expect(kept!.steps.last.state, PlanState.todo);
    expect(out.stdout, contains('[x] 看用量'));
    expect(out.stdout, contains('[>] 删旧日志'));
  });

  test('一步都不写就如实说不行', () async {
    final PlanTool tool = PlanTool();
    final ToolOutcome out = await tool.run(<String, Object?>{'steps': <Object?>[]}, _ctx);
    expect(out.ok, isFalse);
    expect(tool.plan, isNull);
  });
}
