import 'package:flutter/material.dart';

import '../core/agent.dart';
import '../core/models.dart';
import 'theme.dart';

/// A hairline. The only separator this interface uses.
class RuleLine extends StatelessWidget {
  const RuleLine({super.key, this.strong = false, this.height = 1});

  final bool strong;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      color: strong ? C.ink : C.rule,
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(), style: C.label);
  }
}

class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key, this.mono = true});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(fontSize: 12, color: C.grey)),
          ),
          Expanded(
            child: Text(
              value,
              style: mono ? C.monoSmall.copyWith(color: C.ink) : C.answer,
            ),
          ),
        ],
      ),
    );
  }
}

/// Square button. Filled means the main action, outlined means the other one.
class SquareButton extends StatelessWidget {
  const SquareButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final Color fg = filled ? C.paper : (danger ? C.grey : C.ink);
    final Color? bg = filled ? C.ink : null;
    return SizedBox(
      height: 36,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(color: C.ink),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          minimumSize: const Size(0, 36),
          textStyle: const TextStyle(fontSize: 13),
        ),
        child: Text(label),
      ),
    );
  }
}

/// One tool call: a status rule on the left, then name, command and output.
class ToolCallCard extends StatelessWidget {
  const ToolCallCard({
    super.key,
    required this.call,
    this.output,
    this.running = false,
  });

  final LlmToolCall call;
  final String? output;
  final bool running;

  Color get _bar {
    if (running) return C.blue;
    if (output == null) return C.rule2;
    return C.ink;
  }

  String get _command {
    final Object? raw = call.args['command'] ?? call.args['path'] ?? call.args['url'];
    return '${raw ?? ''}';
  }

  @override
  Widget build(BuildContext context) {
    final String text = output ?? '';
    final List<String> lines = text.split('\n');
    final bool long = lines.length > 12;
    final String shown = long ? lines.take(12).join('\n') : text;
    final int rest = long ? lines.length - 12 : 0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(width: 3, height: null, constraints: const BoxConstraints(minHeight: 44), color: _bar),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: <Widget>[
                    Text(call.name, style: C.monoSmall.copyWith(color: C.ink)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        running ? '执行中' : (output == null ? '等待' : '完成'),
                        style: C.monoSmall.copyWith(color: running ? C.blue : C.grey2),
                      ),
                    ),
                  ],
                ),
              ),
              if (_command.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _command,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: C.mono.copyWith(fontSize: 11.5),
                  ),
                ),
              if (shown.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  color: C.paper2,
                  child: Text(shown, style: C.output),
                ),
              if (rest > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text('还有 $rest 行', style: C.monoSmall.copyWith(color: C.grey2)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The one block that must be read before anything runs.
class ApprovalCard extends StatelessWidget {
  const ApprovalCard({
    super.key,
    required this.request,
    required this.onDecide,
  });

  final ApprovalRequest request;
  final void Function(bool allowed) onDecide;

  String get _command {
    final Map<String, Object?> args = request.args;
    final String summary = request.summary;
    final Object? raw = args['command'] ?? args['path'] ?? args['url'] ?? args['note'];
    final String detail = '${raw ?? ''}';
    return detail.isEmpty ? summary : detail;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const RuleLine(strong: true, height: 2),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(width: 3, color: C.blue, constraints: const BoxConstraints(minHeight: 120)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('待批准', style: C.label.copyWith(color: C.blue)),
                    const SizedBox(height: 8),
                    Text(
                      '${request.tool.name} · ${request.summary}',
                      style: C.monoSmall.copyWith(color: C.grey),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.only(left: 10),
                      decoration: const BoxDecoration(
                        border: Border(left: BorderSide(color: C.rule2)),
                      ),
                      child: Text(_command, style: C.mono.copyWith(fontSize: 12.5)),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        SquareButton(label: '拒绝', onPressed: () => onDecide(false)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SquareButton(
                            label: '批准执行',
                            filled: true,
                            onPressed: () => onDecide(true),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const RuleLine(),
      ],
    );
  }
}

/// Labelled text field with a rule under it instead of a box.
class RuleField extends StatelessWidget {
  const RuleField({
    super.key,
    required this.controller,
    required this.label,
    this.hint = '',
    this.obscure = false,
    this.keyboard = TextInputType.text,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscure;
  final TextInputType keyboard;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionLabel(label),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboard,
          minLines: minLines,
          maxLines: obscure ? 1 : maxLines,
          style: C.mono.copyWith(fontSize: 13),
        ),
        const SizedBox(height: 4),
        const RuleLine(),
        const SizedBox(height: 18),
      ],
    );
  }
}
