import 'dart:async';

import 'package:flutter/material.dart';

import '../core/schedule.dart';
import '../data/hosts.dart';
import '../data/tasks.dart';
import 'components.dart';
import 'theme.dart';

/// 定时任务：清单、开关、跑一次的记录，都在这一页。
class TasksPage extends StatefulWidget {
  const TasksPage({
    super.key,
    required this.tasks,
    required this.scheduler,
    required this.hosts,
    required this.onChanged,
  });

  final TaskStore tasks;
  final TaskScheduler scheduler;
  final HostStore hosts;
  final VoidCallback onChanged;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // 只为了让「还有 5 小时」这句跟着走，任务本身的计时在调度器里。
    _ticker = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  List<ScheduledTask> get _list {
    final List<ScheduledTask> all = List<ScheduledTask>.of(widget.tasks.all);
    all.sort((ScheduledTask a, ScheduledTask b) {
      if (a.enabled != b.enabled) return a.enabled ? -1 : 1;
      final DateTime? x = a.nextAt;
      final DateTime? y = b.nextAt;
      if (x == null && y == null) return a.title.compareTo(b.title);
      if (x == null) return 1;
      if (y == null) return -1;
      return x.compareTo(y);
    });
    return all;
  }

  String _hostName(String id) {
    if (id.isEmpty) return '全部主机';
    final HostEntry? h = widget.hosts.byId(id);
    return h == null ? '主机已删除' : h.name;
  }

  @override
  Widget build(BuildContext context) {
    final List<ScheduledTask> list = _list;
    return Column(
      children: <Widget>[
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            color: C.card,
            border: Border(bottom: BorderSide(color: C.rule)),
          ),
          child: Row(
            children: <Widget>[
              const Text('任务',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
              const SizedBox(width: 8),
              Text('${list.length}', style: C.monoSmall),
              const Spacer(),
              GestureDetector(
                onTap: () => _edit(),
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: C.blue,
                    borderRadius: BorderRadius.circular(C.radiusSmall),
                  ),
                  child: const Icon(Icons.add, size: 17, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? _empty()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  itemCount: list.length,
                  itemBuilder: (BuildContext context, int i) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _card(list[i]),
                  ),
                ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: const Text(
            '定时任务在应用里计时。应用被系统清掉时不会触发，三小时内错过的会在下次打开时补跑一次。'
            '到点后它自己动手，不再问你，只有危险命令会被拦下。',
            style: TextStyle(fontSize: 11, color: C.grey, height: 1.7),
          ),
        ),
      ],
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 34, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('还没有定时任务',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.4)),
          const SizedBox(height: 8),
          const Text(
            '写一句话，定个时间，到点它自己去做。比如每天凌晨看一眼磁盘，每周一早上整理一遍日志。',
            style: C.answer,
          ),
          const SizedBox(height: 20),
          SquareButton(label: '加一个', filled: true, onPressed: () => _edit()),
        ],
      ),
    );
  }

  Widget _card(ScheduledTask task) {
    final DateTime now = DateTime.now();
    final bool running = widget.scheduler.isRunning(task.id);
    final TaskRun? last = task.lastRealRun;

    return CardBox(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: InkWell(
                  onTap: () => _edit(task),
                  child: Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              if (running)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _chip('运行中', fg: C.blue, bg: C.blueSoft),
                )
              else if (!task.enabled)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _chip(task.finished ? '跑过了' : '已停用', fg: C.grey, bg: C.paper2),
                ),
              ToggleKnob(
                value: task.enabled,
                onChanged: (bool v) => _toggle(task, v),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${task.when} · ${_hostName(task.hostId)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: C.monoSmall,
          ),
          const SizedBox(height: 3),
          Text(
            _nextText(task, now),
            style: C.monoSmall.copyWith(color: task.enabled ? C.blue : C.grey2),
          ),
          if (task.prompt.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 7),
            Text(
              task.prompt.trim().replaceAll('\n', ' '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, height: 1.55, color: C.body),
            ),
          ],
          const SizedBox(height: 10),
          const RuleLine(),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              _dot(last),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  last == null
                      ? '还没跑过'
                      : '上次 ${last.stamp}${last.late ? '（补跑）' : ''} · '
                          '${last.ok ? (last.note.isEmpty ? '完成' : last.note) : (last.note.isEmpty ? '失败' : last.note)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: C.monoSmall.copyWith(color: last == null ? C.grey2 : C.grey),
                ),
              ),
              const SizedBox(width: 6),
              _link('跑一次', running ? null : () => _runNow(task), primary: true),
              _link('记录', task.runs.isEmpty ? null : () => _history(task)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dot(TaskRun? last) {
    final Color color = last == null
        ? C.rule2
        : last.ok
            ? const Color(0xFF3FA96B)
            : const Color(0xFFD7443E);
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _chip(String text, {required Color fg, required Color bg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: C.monoSmall.copyWith(fontSize: 10, color: fg, height: 1.4)),
    );
  }

  Widget _link(String label, VoidCallback? onTap, {bool primary = false}) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: primary ? C.blue : C.grey,
        disabledForegroundColor: C.grey2,
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }

  String _nextText(ScheduledTask task, DateTime now) {
    if (!task.enabled) {
      return task.finished ? '不会再跑了' : '停用了，不会自己跑';
    }
    final DateTime? at = task.nextAt;
    if (at == null) return '还没有排上';
    return '下次 ${stampText(at, now: now)} · ${untilText(at, now)}';
  }

  Future<void> _toggle(ScheduledTask task, bool value) async {
    task.enabled = value;
    task.reschedule(DateTime.now());
    await widget.tasks.upsert(task);
    if (!mounted) return;
    setState(() {});
    widget.onChanged();
    if (value && task.kind == ScheduleKind.once && task.nextAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这个任务的时间已经过去了，改一下时间才会跑。')),
      );
    }
  }

  Future<void> _runNow(ScheduledTask task) async {
    setState(() {});
    await widget.scheduler.runNow(task);
    if (!mounted) return;
    setState(() {});
    widget.onChanged();
  }

  Future<void> _edit([ScheduledTask? task]) async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => TaskEditorPage(
          task: task,
          hosts: widget.hosts,
          store: widget.tasks,
        ),
      ),
    );
    if (saved != true || !mounted) return;
    setState(() {});
    widget.onChanged();
  }

  void _history(ScheduledTask task) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0x00000000),
      builder: (BuildContext ctx) => _HistorySheet(task: task),
    );
  }
}

/// 一条任务的运行记录。回答全文折叠着，点了才展开。
class _HistorySheet extends StatefulWidget {
  const _HistorySheet({required this.task});

  final ScheduledTask task;

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  int _open = -1;

  @override
  Widget build(BuildContext context) {
    final List<TaskRun> runs = widget.task.runs;
    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: const BoxDecoration(
        color: C.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: <Widget>[
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: C.card,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(bottom: BorderSide(color: C.rule)),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text('${widget.task.title} · 记录 ${runs.length} 条',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 18, color: C.grey),
                ),
              ],
            ),
          ),
          Expanded(
            child: runs.isEmpty
                ? const Padding(
                    padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: Text('还没跑过。点「跑一次」现在就试。',
                        style: TextStyle(fontSize: 13.5, color: C.body, height: 1.6)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                    itemCount: runs.length,
                    itemBuilder: (BuildContext context, int i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _row(runs[i], i),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _row(TaskRun run, int index) {
    final String state = run.missed ? '错过' : (run.ok ? '完成' : '失败');
    final Color fg = run.missed
        ? C.grey
        : run.ok
            ? const Color(0xFF3FA96B)
            : const Color(0xFFD7443E);
    final bool open = _open == index;
    final String extra = <String>[
      if (run.late) '补跑',
      if (run.steps > 0) '${run.steps} 步',
      if (run.tokens > 0) '${run.tokens} tok',
    ].join(' · ');

    return CardBox(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(run.stamp, style: C.monoSmall.copyWith(color: C.ink)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: run.missed ? C.paper2 : C.blueSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(state,
                    style: C.monoSmall.copyWith(fontSize: 10, color: fg, height: 1.4)),
              ),
              const Spacer(),
              if (extra.isNotEmpty) Text(extra, style: C.monoSmall.copyWith(color: C.grey2)),
            ],
          ),
          if (run.note.isNotEmpty) ...<Widget>[
            const SizedBox(height: 7),
            Text(run.note, style: const TextStyle(fontSize: 13, height: 1.6, color: C.body)),
          ],
          if (run.answer.trim().isNotEmpty && run.answer.trim() != run.note.trim()) ...<Widget>[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => setState(() => _open = open ? -1 : index),
              child: Text(open ? '收起全文' : '看全文',
                  style: C.monoSmall.copyWith(color: C.blue)),
            ),
            if (open)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: C.paper2,
                  borderRadius: BorderRadius.circular(C.radiusSmall),
                ),
                child: SelectableText(run.answer,
                    style: C.output.copyWith(fontSize: 12, height: 1.6)),
              ),
          ],
        ],
      ),
    );
  }
}

/// 新建或改一条定时任务。
class TaskEditorPage extends StatefulWidget {
  const TaskEditorPage({
    super.key,
    required this.task,
    required this.hosts,
    required this.store,
  });

  final ScheduledTask? task;
  final HostStore hosts;
  final TaskStore store;

  @override
  State<TaskEditorPage> createState() => _TaskEditorPageState();
}

class _TaskEditorPageState extends State<TaskEditorPage> {
  late final TextEditingController _title;
  late final TextEditingController _prompt;
  late final TextEditingController _interval;
  late String _hostId;
  late bool _enabled;
  late ScheduleKind _kind;
  late int _minuteOfDay;
  late List<int> _weekdays;
  DateTime? _onceAt;

  @override
  void initState() {
    super.initState();
    final ScheduledTask? t = widget.task;
    _title = TextEditingController(text: t?.title ?? '');
    _prompt = TextEditingController(text: t?.prompt ?? '');
    _interval = TextEditingController(text: '${t?.intervalMinutes ?? 60}');
    _hostId = t?.hostId ?? '';
    _enabled = t?.enabled ?? true;
    _kind = t?.kind ?? ScheduleKind.daily;
    _minuteOfDay = t?.minuteOfDay ?? 180;
    _weekdays = List<int>.of(t?.weekdays ?? <int>[1]);
    _onceAt = t?.onceAt;
  }

  @override
  void dispose() {
    _title.dispose();
    _prompt.dispose();
    _interval.dispose();
    super.dispose();
  }

  bool get _isNew => widget.task == null;

  Future<void> _save() async {
    final String prompt = _prompt.text.trim();
    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先写清楚要它做什么。')),
      );
      return;
    }
    if (_kind == ScheduleKind.weekly && _weekdays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('每周至少选一天。')),
      );
      return;
    }
    if (_kind == ScheduleKind.once && _onceAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('选一下哪一天几点。')),
      );
      return;
    }
    final int minutes = int.tryParse(_interval.text.trim()) ?? 60;
    final ScheduledTask task = widget.task ??
        ScheduledTask(
          id: TaskStore.newId(),
          title: '',
          prompt: '',
        );
    final List<int> days = List<int>.of(_weekdays)..sort();
    task.title = _title.text.trim().isEmpty ? '定时任务' : _title.text.trim();
    task.prompt = prompt;
    task.hostId = _hostId;
    task.enabled = _enabled;
    task.kind = _kind;
    task.minuteOfDay = _minuteOfDay;
    task.weekdays = days;
    task.intervalMinutes = minutes < 5 ? 5 : minutes;
    task.onceAt = _onceAt;
    task.reschedule(DateTime.now());
    await widget.store.upsert(task);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final ScheduledTask? t = widget.task;
    if (t == null) return;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('删掉这个任务？', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text('「${t.title}」和它的运行记录会一起删掉。',
            style: const TextStyle(fontSize: 13, height: 1.6)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消', style: TextStyle(fontSize: 13, color: C.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(fontSize: 13, color: Color(0xFFD7443E))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.remove(t.id);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _pickTime() async {
    final TimeOfDay start =
        TimeOfDay(hour: _minuteOfDay ~/ 60, minute: _minuteOfDay % 60);
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: start,
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (picked == null || !mounted) return;
    setState(() => _minuteOfDay = picked.hour * 60 + picked.minute);
  }

  Future<void> _pickOnce() async {
    final DateTime now = DateTime.now();
    final DateTime base = _onceAt ?? now.add(const Duration(hours: 1));
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 3),
    );
    if (date == null || !mounted) return;
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (time == null || !mounted) return;
    setState(() => _onceAt =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    final List<HostEntry> hosts = widget.hosts.hosts;
    return Scaffold(
      backgroundColor: C.paper,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: const BoxDecoration(
                color: C.card,
                border: Border(bottom: BorderSide(color: C.rule)),
              ),
              child: Row(
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      foregroundColor: C.grey,
                      minimumSize: const Size(0, 36),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    child: const Text('取消'),
                  ),
                  Expanded(
                    child: Text(
                      _isNew ? '新任务' : '改任务',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: _save,
                    style: TextButton.styleFrom(
                      foregroundColor: C.blue,
                      minimumSize: const Size(0, 36),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
                children: <Widget>[
                  RuleField(controller: _title, label: '名字', hint: '磁盘体检'),
                  RuleField(
                    controller: _prompt,
                    label: '做什么',
                    hint: '看看磁盘还剩多少，超过 85% 就说一声',
                    minLines: 4,
                    maxLines: 8,
                  ),
                  const SectionLabel('用哪台主机'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _chip('全部主机', _hostId.isEmpty, () => setState(() => _hostId = '')),
                      for (final HostEntry h in hosts)
                        _chip(h.name, _hostId == h.id, () => setState(() => _hostId = h.id)),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const SectionLabel('什么时候'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _chip('每天', _kind == ScheduleKind.daily,
                          () => setState(() => _kind = ScheduleKind.daily)),
                      _chip('每周', _kind == ScheduleKind.weekly,
                          () => setState(() => _kind = ScheduleKind.weekly)),
                      _chip('每隔一阵', _kind == ScheduleKind.interval,
                          () => setState(() => _kind = ScheduleKind.interval)),
                      _chip('一次', _kind == ScheduleKind.once,
                          () => setState(() => _kind = ScheduleKind.once)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _timeBlock(),
                  const SizedBox(height: 22),
                  CardBox(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text('启用', style: TextStyle(fontSize: 13, color: C.ink)),
                              const SizedBox(height: 3),
                              Text(
                                _preview(),
                                style: C.monoSmall.copyWith(color: C.blue),
                              ),
                            ],
                          ),
                        ),
                        ToggleKnob(
                          value: _enabled,
                          onChanged: (bool v) => setState(() => _enabled = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '到点时它自己动手，不会停下来问你。要人确认的动作会跳过，危险命令在策略里就被拦下。',
                    style: TextStyle(fontSize: 11.5, color: C.grey, height: 1.7),
                  ),
                  if (!_isNew) ...<Widget>[
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 38,
                      child: TextButton(
                        onPressed: _delete,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFD7443E),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(C.radiusSmall),
                            side: const BorderSide(color: C.rule2),
                          ),
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        child: const Text('删掉这个任务'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeBlock() {
    switch (_kind) {
      case ScheduleKind.daily:
        return _pickRow('时间', clockText(_minuteOfDay), _pickTime);
      case ScheduleKind.weekly:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (int d = 1; d <= 7; d += 1)
                  _chip('周${kWeekNames[d - 1]}', _weekdays.contains(d), () {
                    setState(() {
                      if (_weekdays.contains(d)) {
                        _weekdays.remove(d);
                      } else {
                        _weekdays.add(d);
                      }
                    });
                  }),
              ],
            ),
            const SizedBox(height: 12),
            _pickRow('时间', clockText(_minuteOfDay), _pickTime),
          ],
        );
      case ScheduleKind.interval:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final int m in <int>[15, 30, 60, 180, 360, 720, 1440])
                  _chip(_intervalName(m), int.tryParse(_interval.text.trim()) == m, () {
                    setState(() => _interval.text = '$m');
                  }),
              ],
            ),
            const SizedBox(height: 12),
            RuleField(
              controller: _interval,
              label: '每隔多少分钟',
              keyboard: TextInputType.number,
              hint: '60',
              onChanged: (_) => setState(() {}),
            ),
          ],
        );
      case ScheduleKind.once:
        final DateTime? at = _onceAt;
        return _pickRow(
          '哪一天',
          at == null ? '还没选' : '${stampText(at)}',
          _pickOnce,
        );
    }
  }

  String _intervalName(int minutes) {
    if (minutes < 60) return '$minutes 分钟';
    if (minutes % 60 == 0) return '${minutes ~/ 60} 小时';
    return '$minutes 分钟';
  }

  Widget _pickRow(String label, String value, Future<void> Function() onTap) {
    return InkWell(
      onTap: () => onTap(),
      borderRadius: BorderRadius.circular(C.radiusSmall),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: C.card,
          borderRadius: BorderRadius.circular(C.radiusSmall),
          border: Border.all(color: C.rule),
        ),
        child: Row(
          children: <Widget>[
            Text(label, style: const TextStyle(fontSize: 11.5, color: C.grey)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(value, style: C.mono.copyWith(fontSize: 13.5, color: C.ink)),
            ),
            const Icon(Icons.chevron_right, size: 16, color: C.grey2),
          ],
        ),
      ),
    );
  }

  /// 把当前排版念一遍，改时间时不用猜。
  String _preview() {
    final ScheduledTask probe = ScheduledTask(
      id: 'preview',
      title: 'preview',
      prompt: 'preview',
      kind: _kind,
      minuteOfDay: _minuteOfDay,
      weekdays: List<int>.of(_weekdays),
      intervalMinutes: int.tryParse(_interval.text.trim()) ?? 60,
      onceAt: _onceAt,
    );
    final DateTime now = DateTime.now();
    final DateTime? next = probe.nextRunAfter(now);
    if (!_enabled) return '${probe.when} · 已停用';
    if (next == null) return '${probe.when} · 时间已经过去了';
    return '${probe.when} · 下次 ${stampText(next, now: now)}';
  }

  Widget _chip(String label, bool on, VoidCallback tap) {
    return GestureDetector(
      onTap: tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
}
