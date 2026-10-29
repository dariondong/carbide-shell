import 'package:flutter/material.dart';

import '../core/agent.dart';
import '../core/models.dart';
import 'md_text.dart';
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

/// One tool call as a single compact row. Output stays folded until asked
/// for, so a run of commands cannot flood the conversation.
class ToolStepRow extends StatefulWidget {
  const ToolStepRow({
    super.key,
    required this.call,
    this.output,
    this.running = false,
  });

  final LlmToolCall call;
  final String? output;
  final bool running;

  @override
  State<ToolStepRow> createState() => _ToolStepRowState();
}

class _ToolStepRowState extends State<ToolStepRow> {
  bool _open = false;

  /// 这条输出上一次是怎么分的行。命令跑完就不变了，不用每帧再分一次。
  String? _measured;
  String _head = '';
  int _rest = 0;

  @override
  void didUpdateWidget(ToolStepRow old) {
    super.didUpdateWidget(old);
    // A step that starts running opens itself; the user can still fold it.
    if (widget.running && !old.running) _open = true;
  }

  String get _command {
    final Map<String, Object?> a = widget.call.args;
    final Object? raw = a['command'] ?? a['path'] ?? a['url'] ?? a['note'] ?? a['op'];
    return '${raw ?? ''}';
  }

  /// 展开时才分：收着的行连切一次字符串都不用。
  void _measure(String text) {
    if (_measured == text) return;
    _measured = text;
    final List<String> lines = text.split('\n');
    final int shown = lines.length > 200 ? 200 : lines.length;
    _rest = lines.length - shown;
    _head = lines.take(shown).join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final String text = widget.output ?? '';
    if (_open && text.isNotEmpty) _measure(text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InkWell(
          onTap: text.isEmpty ? null : () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: <Widget>[
                _dot(),
                const SizedBox(width: 9),
                Text(widget.call.name,
                    style: C.monoSmall.copyWith(
                      color: C.ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    )),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _command.replaceAll('\n', ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: C.monoSmall.copyWith(fontSize: 11, color: C.grey),
                  ),
                ),
                if (text.isNotEmpty)
                  Icon(
                    _open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 16,
                    color: C.grey2,
                  ),
              ],
            ),
          ),
        ),
        if (_open && text.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: C.paper2,
              borderRadius: BorderRadius.circular(C.radiusSmall),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                LinkText(text: _head, style: C.output),
                if (_rest > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('还有 $_rest 行没有显示',
                        style: C.monoSmall.copyWith(color: C.grey2, fontSize: 10.5)),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _dot() {
    final Color color = widget.running
        ? C.blue
        : (widget.output == null ? C.rule2 : const Color(0xFF3FA96B));
    if (widget.running) {
      return SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(strokeWidth: 1.6, color: color),
      );
    }
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Several calls from one assistant turn, folded into one card.
class ToolRunGroup extends StatelessWidget {
  const ToolRunGroup({
    super.key,
    required this.calls,
    required this.outputs,
    this.runningId = '',
  });

  final List<LlmToolCall> calls;
  final Map<String, String> outputs;
  final String runningId;

  @override
  Widget build(BuildContext context) {
    if (calls.length == 1) {
      final LlmToolCall c = calls.first;
      return ToolStepRow(
        call: c,
        output: outputs[c.id],
        running: c.id == runningId,
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(C.radiusSmall),
        border: Border.all(color: C.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Text('${calls.length} 步操作', style: C.label),
          ),
          for (int i = 0; i < calls.length; i += 1) ...<Widget>[
            if (i > 0) const RuleLine(),
            ToolStepRow(
              call: calls[i],
              output: outputs[calls[i].id],
              running: calls[i].id == runningId,
            ),
          ],
        ],
      ),
    );
  }
}

/// The block that has to be read before anything runs.
class ApprovalCard extends StatelessWidget {
  const ApprovalCard({
    super.key,
    required this.request,
    required this.onDecide,
    this.onAllowKind,
    this.onAllowAll,
    this.kindLabel = '',
  });

  final ApprovalRequest request;
  final void Function(bool allowed) onDecide;

  /// Approve this shape of command for the rest of the conversation.
  final VoidCallback? onAllowKind;

  /// Approve everything for the rest of the conversation.
  final VoidCallback? onAllowAll;

  final String kindLabel;

  String get _command {
    final Map<String, Object?> args = request.args;
    final Object? raw = args['command'] ??
        args['path'] ??
        args['url'] ??
        args['note'] ??
        args['text'] ??
        args['value'] ??
        args['key'];
    final String detail = '${raw ?? ''}';
    return detail.isEmpty ? request.summary : detail;
  }

  /// 这张卡执行下去会发生什么。做的是哪件事就说哪件事，不一律说成命令。
  String get _note => switch (request.tool.name) {
        'ssh_exec' => '批准后这条命令会在目标主机上执行。危险命令已经在上一步被拦掉了。',
        'tune_param' => '批准后这套配置的参数就换成新值，之后的消息按新值走。被锁住的参数会回一句改不了。',
        'env_set' || 'env_delete' => '批准后只动本机安全存储里的环境密钥，值不进对话记录，也不写日志。',
        'mail_send' => '批准后才发出去，收件人就是上面这个。',
        'sms_send' => '批准后会用本机号码发出这条短信。',
        _ => '批准后这一步会执行。',
      };

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
          Text(
            _note,
            style: const TextStyle(fontSize: 12, height: 1.6, color: C.grey),
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
                  label: '批准这一条',
                  filled: true,
                  onPressed: () => onDecide(true),
                ),
              ),
            ],
          ),
          if (onAllowKind != null || onAllowAll != null) ...<Widget>[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              children: <Widget>[
                if (onAllowKind != null)
                  TextButton(
                    onPressed: onAllowKind,
                    style: TextButton.styleFrom(
                      foregroundColor: C.blue,
                      textStyle: const TextStyle(fontSize: 12),
                      minimumSize: const Size(0, 32),
                    ),
                    child: Text('这一类都批准${kindLabel.isEmpty ? '' : '（$kindLabel）'}'),
                  ),
                if (onAllowAll != null)
                  TextButton(
                    onPressed: onAllowAll,
                    style: TextButton.styleFrom(
                      foregroundColor: C.grey,
                      textStyle: const TextStyle(fontSize: 12),
                      minimumSize: const Size(0, 32),
                    ),
                    child: const Text('这个对话都批准'),
                  ),
              ],
            ),
          ],
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
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscure;
  final TextInputType keyboard;
  final int minLines;
  final int maxLines;
  final void Function(String text)? onChanged;

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
            onChanged: onChanged,
            style: C.mono.copyWith(fontSize: 13),
            decoration: InputDecoration(hintText: hint.isEmpty ? null : hint),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// 一枚开关。不用 Material 那个，免得系统主题把它染成别的颜色。
class ToggleKnob extends StatelessWidget {
  const ToggleKnob({super.key, required this.value, required this.onChanged});

  final bool value;
  final void Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 44,
        height: 26,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? C.blue : C.rule2,
          borderRadius: BorderRadius.circular(13),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

/// 一块底部面板的白卡：圆角顶、一条抓手，键盘弹起来时整块跟着上去。
class SheetCard extends StatelessWidget {
  const SheetCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(18, 8, 18, 14),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: C.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: padding,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: C.rule2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// 面板的标题行：一句话 + 右边那个文件。
class SheetHead extends StatelessWidget {
  const SheetHead({super.key, required this.title, required this.note});

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, color: C.ink)),
              const SizedBox(height: 3),
              Text(note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: C.monoSmall),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          behavior: HitTestBehavior.opaque,
          child: const SizedBox(
            width: 30,
            height: 30,
            child: Icon(Icons.close, size: 17, color: C.grey),
          ),
        ),
      ],
    );
  }
}
