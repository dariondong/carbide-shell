import 'package:flutter/material.dart';

import '../core/triggers.dart';
import '../data/triggers.dart';
import 'components.dart';
import 'motion.dart';
import 'pet.dart';
import 'theme.dart';

/// 触发器：手机状态、消息通知、定时，三种条件配两种动作。
///
/// 每一行写得下一眼就明白：什么条件、做什么、上回跑成什么样。
/// 手机状态那一条跑起来要过模型判断，判断依据与结果都留在下面的记录里。
class TriggersPage extends StatefulWidget {
  const TriggersPage({
    super.key,
    required this.triggers,
    required this.runner,
    required this.onChanged,
  });

  final TriggerStore triggers;
  final TriggerRunner runner;
  final VoidCallback onChanged;

  @override
  State<TriggersPage> createState() => _TriggersPageState();
}

class _TriggersPageState extends State<TriggersPage> {
  bool _busy = false;

  List<Trigger> get _list => widget.triggers.all;

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save(Trigger t) async {
    await widget.triggers.upsert(t);
    widget.onChanged();
    if (mounted) setState(() {});
  }

  Future<void> _toggle(Trigger t, bool on) async {
    t.enabled = on;
    if (on) t.nextAt = nextDueAt(t, DateTime.now());
    await _save(t);
  }

  Future<void> _remove(Trigger t) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('删掉这条触发器？',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text('${t.title} 和它的运行记录一起删掉。',
            style: const TextStyle(fontSize: 13, height: 1.6)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('再想想', style: TextStyle(fontSize: 13, color: C.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(fontSize: 13, color: C.blue)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await widget.triggers.remove(t.id);
    widget.onChanged();
    setState(() {});
  }

  Future<void> _runNow(Trigger t) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final String note = await widget.runner.runNow(t);
      widget.onChanged();
      if (mounted) setState(() {});
      _toast(note.isEmpty ? '跑完了，没留记录' : note);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(Trigger t) async {
    await widget.runner.approve(t);
    widget.onChanged();
    if (mounted) setState(() {});
  }

  Future<void> _dismiss(Trigger t) async {
    await widget.runner.dismiss(t);
    widget.onChanged();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.paper,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: const BoxDecoration(
                color: C.card,
                border: Border(bottom: BorderSide(color: C.rule)),
              ),
              child: Row(
                children: <Widget>[
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back, size: 19, color: C.ink),
                  ),
                  const Text('触发器',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Text('${_list.length} 条', style: C.monoSmall),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _edit(),
                    style: TextButton.styleFrom(
                      foregroundColor: C.blue,
                      minimumSize: const Size(0, 34),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    child: const Text('加一条'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
                children: <Widget>[
                  if (_list.isEmpty) ...<Widget>[
                    const PetAvatar(size: 84),
                    const SizedBox(height: 10),
                    const Text(
                      '还没有触发器。加一条试试：手机插上电时发一句通知，或者来了某个关键词的通知就让模型先看一眼。',
                      style: TextStyle(fontSize: 12.5, color: C.grey, height: 1.7),
                    ),
                  ],
                  for (final Trigger t in _list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: FadeSlideIn(child: _card(t)),
                    ),
                  const SizedBox(height: 10),
                  const Text(
                    '手机状态那一种由模型判断，判断依据、把握和结果都写在这条触发器的记录里。'
                    '触发器跑起来时没有人守着，需要确认的操作一律拒绝，所以它只做读的事。',
                    style: TextStyle(fontSize: 11, color: C.grey, height: 1.7),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(Trigger t) {
    final TriggerRun? last = t.runs.isEmpty ? null : t.runs.first;
    final bool waiting = last != null && last.status == TriggerRunStatus.waiting;
    return CardBox(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              ToggleKnob(value: t.enabled, onChanged: (bool v) => _toggle(t, v)),
            ],
          ),
          const SizedBox(height: 4),
          Text(_conditionLine(t),
              style: const TextStyle(fontSize: 11.5, color: C.grey, height: 1.55)),
          const SizedBox(height: 2),
          Text('→ ${triggerActionName(t.action)}${t.actionText.trim().isEmpty ? '' : '：${_clip(t.actionText.trim(), 40)}'}',
              style: const TextStyle(fontSize: 11.5, color: C.ink, height: 1.55)),
          if (t.enabled && t.nextAt != null) ...<Widget>[
            const SizedBox(height: 2),
            Text('下一次看它：${_when(t.nextAt!)}', style: C.monoSmall.copyWith(fontSize: 10.5)),
          ],
          if (last != null) ...<Widget>[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: C.paper2,
                borderRadius: BorderRadius.circular(C.radiusSmall),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${_when(last.at)} · ${triggerStatusName(last.status)}',
                    style: C.monoSmall.copyWith(
                      fontSize: 10.5,
                      color: last.status == TriggerRunStatus.failed ? C.ink : C.grey,
                    ),
                  ),
                  if (last.note.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(last.note,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: C.ink, height: 1.5)),
                  ],
                ],
              ),
            ),
          ],
          if (waiting) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: SquareButton(
                    label: '放弃',
                    tone: 'ink',
                    onPressed: () => _dismiss(t),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SquareButton(
                    label: '这就做',
                    filled: true,
                    onPressed: () => _approve(t),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          const RuleLine(),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              _link(_busy ? '跑着…' : '试一次', _busy ? null : () => _runNow(t)),
              const SizedBox(width: 16),
              _link('改', () => _edit(existing: t)),
              const SizedBox(width: 16),
              _link('删除', () => _remove(t), ink: false),
            ],
          ),
        ],
      ),
    );
  }

  Widget _link(String label, VoidCallback? onTap, {bool ink = true}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(label,
            style: TextStyle(fontSize: 11.5, color: ink ? C.blue : C.grey)),
      ),
    );
  }

  String _conditionLine(Trigger t) {
    switch (t.kind) {
      case TriggerKind.phone:
        final String what = t.intent.trim().isEmpty ? '（还没写条件）' : t.intent.trim();
        final String signals = t.signals.isEmpty
            ? '全部可用信号'
            : t.signals.map(signalLabel).join('、');
        return '手机状态：$what\n看 $signals · 每 ${t.everyMinutes} 分钟判断一次'
            '${t.confirm ? ' · 做之前问你' : ''}';
      case TriggerKind.message:
        return '消息通知：出现 ${t.keywords.isEmpty ? '（还没写关键词）' : t.keywords.join('、')}'
            ' 时 · 每 ${t.everyMinutes} 分钟看一次';
      case TriggerKind.schedule:
        if (t.atTime.trim().isNotEmpty) return '定时：每天 ${t.atTime.trim()}';
        return '定时：每 ${t.everyMinutes} 分钟一次';
    }
  }

  /// 加一条或者改一条。字段按条件类型显示不同的几格。
  Future<void> _edit({Trigger? existing}) async {
    final Trigger draft = existing ??
        Trigger(id: widget.triggers.nextId(), everyMinutes: 15, signals: <String>[]);
    final TextEditingController name = TextEditingController(text: draft.name);
    final TextEditingController intent = TextEditingController(text: draft.intent);
    final TextEditingController atTime = TextEditingController(text: draft.atTime);
    final TextEditingController every = TextEditingController(text: '${draft.everyMinutes}');
    final TextEditingController actionText = TextEditingController(text: draft.actionText);
    TriggerKind kind = draft.kind;
    TriggerActionKind action = draft.action;
    bool confirm = draft.confirm;
    final Set<String> signals = draft.signals.toSet();

    final bool? ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setSheet) => SheetCard(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.78,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(existing == null ? '加一条触发器' : '改这条触发器',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: TextButton.styleFrom(
                        foregroundColor: C.grey,
                        minimumSize: const Size(0, 32),
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                      child: const Text('取消'),
                    ),
                  ],
                ),
                Expanded(
                  child: ListView(
                    children: <Widget>[
                      RuleField(controller: name, label: '名字', hint: '自己认得出就行'),
                      const _Label('条件'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          for (final TriggerKind k in TriggerKind.values)
                            _pick(triggerKindName(k), k == kind,
                                () => setSheet(() => kind = k)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (kind == TriggerKind.phone) ...<Widget>[
                        RuleField(
                          controller: intent,
                          label: '什么状态算触发',
                          hint: '例如：手机插上电并且锁着屏',
                          minLines: 2,
                          maxLines: 4,
                        ),
                        const _Label('允许 AI 参考的信号'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            for (final SignalOption s in kSignalOptions)
                              _pick(s.label, signals.contains(s.key), () {
                                setSheet(() {
                                  if (signals.contains(s.key)) {
                                    signals.remove(s.key);
                                  } else {
                                    signals.add(s.key);
                                  }
                                });
                              }),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text('一项都不选就是全部可用的都看。系统没给的那几项本来也不会有。',
                            style: TextStyle(fontSize: 11, color: C.grey, height: 1.6)),
                        const SizedBox(height: 14),
                      ],
                      if (kind == TriggerKind.message)
                        RuleField(
                          controller: intent,
                          label: '关键词',
                          hint: '逗号分开，例如：备份, 完成',
                          minLines: 1,
                          maxLines: 3,
                        ),
                      if (kind == TriggerKind.schedule) ...<Widget>[
                        RuleField(
                          controller: atTime,
                          label: '每天几点（留空就按间隔）',
                          hint: '08:30',
                        ),
                      ],
                      RuleField(
                        controller: every,
                        label: '多久看一次（分钟）',
                        hint: '15',
                        keyboard: TextInputType.number,
                      ),
                      const _Label('做什么'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          for (final TriggerActionKind a in TriggerActionKind.values)
                            _pick(triggerActionName(a), a == action,
                                () => setSheet(() => action = a)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      RuleField(
                        controller: actionText,
                        label: action == TriggerActionKind.notify
                            ? '通知写什么'
                            : '让模型做什么',
                        hint: action == TriggerActionKind.notify
                            ? '留空就只写触发原因'
                            : '例如：看一下这台机器的磁盘，超过八成就在结论里说一句',
                        minLines: 3,
                        maxLines: 6,
                      ),
                      _toggleRow(
                        '做之前问我一句',
                        confirm && action == TriggerActionKind.prompt,
                        action != TriggerActionKind.prompt
                            ? null
                            : (bool v) => setSheet(() => confirm = v),
                        note: action == TriggerActionKind.prompt
                            ? '判断成立时先发一条通知，你在这一页点「这就做」才跑'
                            : '发通知本身不用再问',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: SquareButton(
                    label: existing == null ? '加上' : '存下',
                    filled: true,
                    onPressed: () => Navigator.of(ctx).pop(true),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final String typedName = name.text.trim();
    final String typedIntent = intent.text.trim();
    final String typedAt = atTime.text.trim();
    final int typedEvery = int.tryParse(every.text.trim()) ?? 15;
    final String typedAction = actionText.text.trim();
    name.dispose();
    intent.dispose();
    atTime.dispose();
    every.dispose();
    actionText.dispose();
    if (ok != true || !mounted) return;

    if (kind == TriggerKind.phone && typedIntent.isEmpty) {
      _toast('先写一句什么状态算触发。');
      return;
    }
    if (kind == TriggerKind.message && typedIntent.isEmpty) {
      _toast('先写要盯的关键词。');
      return;
    }
    if (kind == TriggerKind.schedule &&
        typedAt.isEmpty &&
        (typedEvery <= 0)) {
      _toast('写个时间，或者给个分钟数。');
      return;
    }

    draft
      ..name = typedName
      ..kind = kind
      ..intent = typedIntent
      ..atTime = kind == TriggerKind.schedule ? typedAt : ''
      ..everyMinutes = typedEvery < 1 ? 1 : typedEvery
      ..action = action
      ..actionText = typedAction
      ..confirm = confirm && action == TriggerActionKind.prompt;
    if (kind == TriggerKind.phone) {
      draft.signals = signals.toList();
    } else {
      draft.signals = <String>[];
    }
    draft.nextAt = nextDueAt(draft, DateTime.now());
    await _save(draft);
    _toast(existing == null ? '加上了，开着就会跑。' : '改好了。');
  }

  Widget _pick(String label, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? C.blue : C.card,
          borderRadius: BorderRadius.circular(C.radiusSmall),
          border: Border.all(color: on ? C.blue : C.rule2),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 12, color: on ? Colors.white : C.ink)),
      ),
    );
  }

  Widget _toggleRow(String label, bool value, void Function(bool)? onChanged, {String note = ''}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label,
                    style: TextStyle(
                        fontSize: 13, color: onChanged == null ? C.grey2 : C.ink)),
                if (note.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(note,
                      style: const TextStyle(fontSize: 11, color: C.grey, height: 1.5)),
                ],
              ],
            ),
          ),
          if (onChanged != null)
            ToggleKnob(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  static String _clip(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';

  static String _when(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
  }
}

/// 表单里那行小标签。
class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 11.5, color: C.grey)),
    );
  }
}
