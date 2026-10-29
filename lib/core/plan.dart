/// 这一趟要做的事：一句话的目标，加几步清单。
///
/// 模型用 `plan` 工具写它，对话顶上照着画一排。不落进对话正文，免得每一步都刷一大段。
library;

/// 一步的状态。
enum PlanState { todo, doing, done }

/// 模型写什么的都收：`doing` / `进行中` 都算在做，认不出的算没开始。
PlanState planStateOf(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'doing':
    case 'now':
    case 'run':
    case '进行中':
    case '在做':
      return PlanState.doing;
    case 'done':
    case 'ok':
    case 'finish':
    case 'finished':
    case '完成':
    case '做完':
      return PlanState.done;
    default:
      return PlanState.todo;
  }
}

class PlanStep {
  const PlanStep({required this.title, this.state = PlanState.todo});

  factory PlanStep.fromJson(Map<String, Object?> json) => PlanStep(
        title: '${json['title'] ?? ''}'.trim(),
        state: planStateOf('${json['state'] ?? ''}'),
      );

  final String title;
  final PlanState state;

  Map<String, Object?> toJson() => <String, Object?>{
        'title': title,
        'state': state.name,
      };
}

class WorkPlan {
  WorkPlan({this.goal = '', List<PlanStep>? steps, DateTime? updatedAt})
      : steps = steps ?? <PlanStep>[],
        updatedAt = updatedAt ?? DateTime.now();

  final String goal;
  final List<PlanStep> steps;
  final DateTime updatedAt;

  int get doneCount => steps.where((PlanStep s) => s.state == PlanState.done).length;

  bool get finished => steps.isNotEmpty && doneCount == steps.length;

  /// 「4 步 · 做完 2 步」这一行。
  String get headline =>
      steps.isEmpty ? '还没有步骤' : '${steps.length} 步 · 做完 $doneCount 步';

  Map<String, Object?> toJson() => <String, Object?>{
        'goal': goal,
        'steps': steps.map((PlanStep s) => s.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// 读不出来的就当没有计划，不给界面留半张卡。
  static WorkPlan? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Object? list = raw['steps'];
    final List<PlanStep> steps = <PlanStep>[];
    if (list is List) {
      for (final Object? item in list) {
        if (item is! Map) continue;
        final PlanStep step = PlanStep.fromJson(Map<String, Object?>.from(item));
        if (step.title.isNotEmpty) steps.add(step);
      }
    }
    if (steps.isEmpty) return null;
    return WorkPlan(
      goal: '${raw['goal'] ?? ''}'.trim(),
      steps: steps,
      updatedAt: DateTime.tryParse('${raw['updatedAt'] ?? ''}') ?? DateTime.now(),
    );
  }

  /// 给模型看的那几行，工具结果里原样回过去。
  String render() {
    final StringBuffer b = StringBuffer();
    if (goal.isNotEmpty) b.writeln('目标：$goal');
    b.writeln(headline);
    for (int i = 0; i < steps.length; i += 1) {
      final String mark = switch (steps[i].state) {
        PlanState.done => '[x]',
        PlanState.doing => '[>]',
        PlanState.todo => '[ ]',
      };
      b.writeln('${i + 1}. $mark ${steps[i].title}');
    }
    return b.toString().trimRight();
  }
}
