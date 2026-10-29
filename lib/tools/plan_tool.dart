import '../core/models.dart';
import '../core/plan.dart';
import '../core/tools.dart';

/// `plan`：把这一趟要做的事写成清单。人在对话顶上看得见走到哪一步。
///
/// 它不改机器上的任何东西，只是记下来，所以不设确认。
class PlanTool extends Tool {
  PlanTool({this.plan, this.onChanged});

  /// 这场对话现在的计划。
  WorkPlan? plan;

  /// 写完之后交给对话，界面照着重画。
  final void Function(WorkPlan plan)? onChanged;

  @override
  String get name => 'plan';

  @override
  String get description =>
      '把这一趟要做的事写成清单摆在对话顶上：一句话的目标加几步，每步标 todo / doing / done。'
      '一件事要三步以上才做得完就先写一遍，每做完一步再写一遍更新状态，不要只在回答里叙述。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'goal': <String, Object?>{
            'type': 'string',
            'description': '这一趟要做成什么，一句话',
          },
          'steps': <String, Object?>{
            'type': 'array',
            'description': '整份清单，不是增量：没变的步骤也照写',
            'items': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'title': <String, Object?>{
                  'type': 'string',
                  'description': '这一步做什么，一句话',
                },
                'state': <String, Object?>{
                  'type': 'string',
                  'enum': <String>['todo', 'doing', 'done'],
                  'description': '没开始 / 在做 / 做完',
                },
              },
              'required': <String>['title'],
            },
          },
        },
        'required': <String>['steps'],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.read;

  @override
  String summarize(Map<String, Object?> args) {
    final List<PlanStep> steps = _stepsOf(args);
    return steps.isEmpty ? '写计划' : '计划 ${steps.length} 步';
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final List<PlanStep> steps = _stepsOf(args);
    if (steps.isEmpty) {
      return const ToolOutcome.failure('steps 里至少要写一步。');
    }
    final WorkPlan next = WorkPlan(
      goal: readString(args, 'goal').trim(),
      steps: steps,
    );
    plan = next;
    onChanged?.call(next);
    return ToolOutcome.success(
      stdout: next.render(),
      meta: <String, Object?>{'steps': steps.length, 'done': next.doneCount},
    );
  }

  List<PlanStep> _stepsOf(Map<String, Object?> args) {
    final Object? raw = args['steps'];
    final List<PlanStep> out = <PlanStep>[];
    if (raw is! List) return out;
    for (final Object? item in raw) {
      if (item is String) {
        final String title = item.trim();
        if (title.isNotEmpty) out.add(PlanStep(title: title));
        continue;
      }
      if (item is! Map) continue;
      final Map<String, Object?> one = Map<String, Object?>.from(item);
      final String title = readString(one, 'title').trim();
      if (title.isEmpty) continue;
      out.add(PlanStep(title: title, state: planStateOf(readString(one, 'state'))));
    }
    return out;
  }
}
