import 'package:flutter/material.dart';

import '../core/plan.dart';
import 'motion.dart';
import 'theme.dart';

/// 计划条：钉在对话上方，不跟着记录一起滚。
///
/// 默认展开，点一下收成一行「4 步 · 做完 2 步」，再看记录时它只占一条。
class PlanBar extends StatefulWidget {
  const PlanBar({
    super.key,
    required this.plan,
    this.pad = const EdgeInsets.fromLTRB(12, 10, 12, 0),
  });

  final WorkPlan plan;

  /// 外面的留白。钉在顶栏下面时留住左右 12，已经落进记录里的那一张不留。
  final EdgeInsets pad;

  @override
  State<PlanBar> createState() => _PlanBarState();
}

class _PlanBarState extends State<PlanBar> {
  bool _open = true;

  @override
  void didUpdateWidget(PlanBar old) {
    super.didUpdateWidget(old);
    // 换了一份新计划（比如又来一轮）就把展开状态放回来。
    if (!identical(old.plan, widget.plan)) _open = true;
  }

  @override
  Widget build(BuildContext context) {
    final WorkPlan plan = widget.plan;
    final List<PlanStep> steps = plan.steps;
    // 步骤多了就在条里自己滚，不截断也不抢对话的地方。
    final double room = (MediaQuery.sizeOf(context).height * 0.26).clamp(132.0, 260.0);
    return Padding(
      padding: widget.pad,
      child: Container(
        decoration: BoxDecoration(
          color: C.card,
          borderRadius: BorderRadius.circular(C.radius),
          border: Border.all(color: plan.finished ? C.rule : C.rule2),
          boxShadow: C.softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            InkWell(
              onTap: () => setState(() => _open = !_open),
              borderRadius: BorderRadius.circular(C.radius),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 10, 10, 9),
                child: Row(
                  children: <Widget>[
                    Icon(
                      plan.finished ? Icons.flag_rounded : Icons.checklist_rtl,
                      size: 13,
                      color: plan.finished ? C.grey : C.blue,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        plan.goal.isEmpty
                            ? (plan.finished ? '这件事做完了' : '这一趟的计划')
                            : plan.goal,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: plan.finished ? C.grey : C.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(plan.headline, style: C.monoSmall.copyWith(fontSize: 10)),
                    Icon(_open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 16, color: C.grey2),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: Motion.swap,
              curve: Motion.curve,
              alignment: Alignment.topCenter,
              child: !_open
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(13, 0, 13, 10),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: room),
                        child: Scrollbar(
                          thumbVisibility: steps.length > 8,
                          child: SingleChildScrollView(
                            padding: EdgeInsets.zero,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                for (int i = 0; i < steps.length; i += 1) _step(steps[i]),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step(PlanStep step) {
    final Widget mark = switch (step.state) {
      PlanState.done => Icon(Icons.check_circle, size: 13, color: C.ok),
      PlanState.doing => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: C.blue, shape: BoxShape.circle),
        ),
      PlanState.todo => Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: C.rule2, shape: BoxShape.circle),
        ),
    };
    final Color color = switch (step.state) {
      PlanState.done => C.grey2,
      PlanState.doing => C.ink,
      PlanState.todo => C.body,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 16, height: 18, child: Center(child: mark)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              step.title,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: color,
                fontWeight: step.state == PlanState.doing ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
