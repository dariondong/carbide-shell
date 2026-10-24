import 'package:flutter/material.dart';

import '../core/agent.dart';
import '../core/models.dart';
import 'theme.dart';

/// A white card. The only container shape this interface uses.
class CardBox extends StatelessWidget {
  const CardBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.border = C.rule,
    this.tint,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color border;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tint ?? C.card,
        borderRadius: BorderRadius.circular(C.radius),
        border: Border.all(color: border),
        boxShadow: C.softShadow,
      ),
      child: child,
    );
  }
}

/// A hairline, used inside cards where a border would be too loud.
class RuleLine extends StatelessWidget {
  const RuleLine({super.key, this.strong = false, this.height = 1});

  final bool strong;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(height: height, color: strong ? C.rule2 : C.rule);
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(label, style: const TextStyle(fontSize: 12.5, color: C.grey)),
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

/// Filled = the one main action on the screen. Outlined otherwise.
class SquareButton extends StatelessWidget {
  const SquareButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.tone = 'accent',
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  /// `accent` for the blue action, `ink` for a quiet one.
  final String tone;

  @override
  Widget build(BuildContext context) {
    final Color accent = tone == 'ink' ? C.ink : C.blue;
    final Color bg = filled ? accent : C.card;
    final Color fg = filled ? Colors.white : (onPressed == null ? C.grey2 : C.ink);
    return SizedBox(
      height: 38,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(C.radiusSmall),
            side: BorderSide(color: filled ? bg : C.rule2),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          minimumSize: const Size(0, 38),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
  }
}

/// One tool call, drawn as a card: header, command, output block.
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

  String get _command {
    final Object? raw = call.args['command'] ?? call.args['path'] ?? call.args['url'] ?? call.args['note'];
    return '${raw ?? ''}';
  }

  @override
  Widget build(BuildContext context) {
    final String text = output ?? '';
    final List<String> lines = text.split('\n');
    final bool long = lines.length > 12;
    final String shown = long ? lines.take(12).join('\n') : text;
    final int rest = long ? lines.length - 12 : 0;

    return CardBox(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(call.name,
                  style: C.monoSmall.copyWith(color: C.ink, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              _status(),
              const Spacer(),
              if (running)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.6, color: C.blue),
                ),
            ],
          ),
          if (_command.isNotEmpty) ...<Widget>[
            const SizedBox(height: 7),
            Text(_command,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: C.mono.copyWith(fontSize: 11.5, color: C.body)),
          ],
          if (shown.isNotEmpty) ...<Widget>[
            const SizedBox(height: 9),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: C.paper2,
                borderRadius: BorderRadius.circular(C.radiusSmall),
              ),
              child: Text(shown, style: C.output),
            ),
          ],
          if (rest > 0)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text('还有 $rest 行', style: C.monoSmall.copyWith(color: C.grey2)),
            ),
        ],
      ),
    );
  }

  Widget _status() {
    if (running) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: C.blueSoft,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('执行中', style: C.monoSmall.copyWith(color: C.blue, fontSize: 10)),
      );
    }
    if (output == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: C.paper2,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('等待', style: C.monoSmall.copyWith(color: C.grey2, fontSize: 10)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: C.paper2,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('完成', style: C.monoSmall.copyWith(color: C.grey, fontSize: 10)),
    );
  }
}

/// The block that has to be read before anything runs.
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
    final Object? raw = args['command'] ?? args['path'] ?? args['url'] ?? args['note'];
    final String detail = '${raw ?? ''}';
    return detail.isEmpty ? request.summary : detail;
  }

  @override
  Widget build(BuildContext context) {
    return CardBox(
      border: const Color(0xFFD9DEF7),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: C.blueSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('待批准',
                    style: C.label.copyWith(color: C.blue, fontSize: 9.5, letterSpacing: 1)),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  request.summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: C.monoSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            decoration: BoxDecoration(
              color: C.paper2,
              borderRadius: BorderRadius.circular(C.radiusSmall),
            ),
            child: Text(_command, style: C.mono.copyWith(fontSize: 12.5, color: C.ink)),
          ),
          const SizedBox(height: 11),
          const Text(
            '批准后这条命令会在目标主机上执行。危险命令已经在上一步被拦掉了。',
            style: TextStyle(fontSize: 12, height: 1.6, color: C.grey),
          ),
          const SizedBox(height: 13),
          Row(
            children: <Widget>[
              Expanded(
                child: SquareButton(
                  label: '拒绝',
                  onPressed: () => onDecide(false),
                  tone: 'ink',
                ),
              ),
              const SizedBox(width: 10),
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
    );
  }
}

/// Text input as a soft filled box, label above.
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
    final int lines = obscure ? 1 : (maxLines < minLines ? minLines : maxLines);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: const TextStyle(fontSize: 11.5, color: C.grey)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: C.card,
            borderRadius: BorderRadius.circular(C.radiusSmall),
            border: Border.all(color: C.rule),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboard,
            minLines: obscure ? 1 : minLines,
            maxLines: lines,
            style: C.mono.copyWith(fontSize: 13),
            decoration: InputDecoration(hintText: hint.isEmpty ? null : hint),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
