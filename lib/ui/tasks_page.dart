import 'dart:async';

import 'package:flutter/material.dart';

import '../core/rules.dart';
import '../core/schedule.dart';
import '../core/watch.dart';
import '../data/hosts.dart';
import '../data/tasks.dart';
import '../data/watch.dart';
import 'components.dart';
import 'task_log_page.dart';
import 'theme.dart';

/// 定时任务：清单、开关、跑一次的记录，都在这一页。
class TasksPage extends StatefulWidget {
  const TasksPage({
    super.key,
    required this.tasks,
    required this.watches,
    required this.scheduler,
    required this.hosts,
    required this.onChanged,
  });

  final TaskStore tasks;
  final WatchStore watches;
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
              Text('${list.length} 定时 · ${widget.watches.all.length} 监听',
                  style: C.monoSmall),
              const Spacer(),
              GestureDetector(
                onTap: _openLog,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: C.card,
                    borderRadius: BorderRadius.circular(C.radiusSmall),
                    border: Border.all(color: C.rule2),
                  ),
                  child: const Icon(Icons.receipt_long_outlined, size: 16, color: C.ink),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _addSheet,
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
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            children: <Widget>[
              const SectionLabel('定时任务'),
              const SizedBox(height: 8),
              if (list.isEmpty)
                _hint('还没有定时任务。定好时间与要做的事，到点自动执行。')
              else
                for (final ScheduledTask task in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _card(task),
                  ),
              const SizedBox(height: 18),
              const SectionLabel('资源监听'),
              const SizedBox(height: 8),
              if (_watchList.isEmpty)
                _hint('还没有监听。选定一台主机的 CPU、内存或磁盘，超过阈值时发一条通知，不调用模型。')
              else
                for (final WatchTask watch in _watchList)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _watchCard(watch),
                  ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: const Text(
            '定时任务在应用里计时。应用被系统清掉时不会触发，三小时内错过的会在下次打开时补跑一次。'
            '到点后自动执行，不再询问；只有危险命令会被拦下。资源监听只读指标，超过阈值时发一条通知。',
            style: TextStyle(fontSize: 11, color: C.grey, height: 1.7),
          ),
        ),
      ],
    );
  }

  /// 所有任务的运行记录摆在一起。
  void _openLog() {
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (BuildContext ctx) => TaskLogPage(tasks: widget.tasks),
    ));
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
              else if (task.waitingGate)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _chip('等条件', fg: C.blue, bg: C.blueSoft),
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
          if (task.gated) ...<Widget>[
            const SizedBox(height: 3),
            Text(
              '满足 ${task.conditionText} 才跑',
              style: C.monoSmall.copyWith(color: C.grey),
            ),
          ],
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

  /// 一段空白时的两行说明。
  Widget _hint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text,
          style: const TextStyle(fontSize: 12.5, height: 1.65, color: C.body)),
    );
  }

  List<WatchTask> get _watchList {
    final List<WatchTask> all = List<WatchTask>.of(widget.watches.all);
    all.sort((WatchTask a, WatchTask b) {
      if (a.enabled != b.enabled) return a.enabled ? -1 : 1;
      return a.title.compareTo(b.title);
    });
    return all;
  }

  /// 加号先问一句：定时任务，还是只看数字的监听。
  Future<void> _addSheet() async {
    final String? pick = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0x00000000),
      builder: (BuildContext ctx) => Container(
        decoration: const BoxDecoration(
          color: C.paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 10, left: 4),
              child: Row(
                children: const <Widget>[
                  Text('加什么',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            CardBox(
              padding: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  _addRow('定时任务', '到点自动执行一件事', 'task', ctx),
                  const RuleLine(),
                  _addRow('资源监听', '过线就推一条通知，不叫模型', 'watch', ctx),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (pick == null || !mounted) return;
    if (pick == 'watch') {
      await _editWatch();
    } else {
      await _edit();
    }
  }

  Widget _addRow(String title, String note, String value, BuildContext ctx) {
    return InkWell(
      onTap: () => Navigator.of(ctx).pop(value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: const TextStyle(fontSize: 13.5, color: C.ink)),
                  const SizedBox(height: 3),
                  Text(note, style: const TextStyle(fontSize: 11.5, color: C.grey)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: C.grey2),
          ],
        ),
      ),
    );
  }

  Widget _watchCard(WatchTask watch) {
    final HostEntry? host = widget.hosts.byId(watch.hostId);
    final WatchHit? last = watch.lastHit;
    final Color dot = last == null
        ? C.rule2
        : last.error.isNotEmpty
            ? const Color(0xFFD7443E)
            : last.fired
                ? C.blue
                : const Color(0xFF3FA96B);
    final String lastText;
    if (last == null) {
      lastText = '还没读过';
    } else if (last.error.isNotEmpty) {
      lastText = '${last.stamp} · 读不到：${last.error}';
    } else {
      lastText = '${last.stamp} · ${watch.valueText(last.value ?? 0)}'
          '${last.fired ? ' · 已提醒' : ''}';
    }
    return CardBox(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: InkWell(
                  onTap: () => _editWatch(watch),
                  child: Text(
                    watch.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              if (!watch.enabled)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _chip('已停用', fg: C.grey, bg: C.paper2),
                ),
              ToggleKnob(
                value: watch.enabled,
                onChanged: (bool v) => _toggleWatch(watch, v),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(watch.when, maxLines: 1, overflow: TextOverflow.ellipsis, style: C.monoSmall),
          const SizedBox(height: 3),
          Text(host == null ? '主机已删除' : host.name,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: C.monoSmall.copyWith(color: C.grey2)),
          const SizedBox(height: 10),
          const RuleLine(),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(lastText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: C.monoSmall.copyWith(color: C.grey)),
              ),
              const SizedBox(width: 6),
              _link('改', () => _editWatch(watch)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _toggleWatch(WatchTask watch, bool value) async {
    watch.enabled = value;
    if (value) {
      watch.scheduleFrom(DateTime.now());
    } else {
      watch.nextAt = null;
    }
    await widget.watches.upsert(watch);
    if (!mounted) return;
    setState(() {});
    widget.onChanged();
  }

  Future<void> _editWatch([WatchTask? watch]) async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _WatchEditorPage(
          watch: watch,
          hosts: widget.hosts,
          store: widget.watches,
        ),
      ),
    );
    if (saved != true || !mounted) return;
    setState(() {});
    widget.onChanged();
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
        const SnackBar(content: Text('这个任务的时间已经过去了，改过时间才会跑。')),
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

  /// 到点先判的这棵树：可以是几条判断，也可以再套一层「或」。
  RuleNode? _condition;

  /// 每个叶子上那个数字框，跟着节点走。
  final Map<RuleNode, TextEditingController> _values =
      <RuleNode, TextEditingController>{};

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
    _condition = t?.condition?.deepCopy();
  }

  @override
  void dispose() {
    _title.dispose();
    _prompt.dispose();
    _interval.dispose();
    for (final TextEditingController c in _values.values) {
      c.dispose();
    }
    _values.clear();
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
    final Object? built = _treeForSave();
    if (built is String) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(built)),
      );
      return;
    }
    final RuleNode? condition = built is RuleNode ? built : null;
    if (condition != null && _hostId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('要看条件就得先选一台主机。')),
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
    task.condition = condition;
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
                    hint: '看磁盘使用率，超过 85% 时说明情况',
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
                  const SectionLabel('先看条件'),
                  const SizedBox(height: 6),
                  const Text(
                    '到点先读这台机器的数字，符合了才叫它动手。不符合就隔一会儿再看，窗口过了这一轮就不跑。',
                    style: TextStyle(fontSize: 11.5, color: C.grey, height: 1.7),
                  ),
                  const SizedBox(height: 10),
                  _conditionEditor(),
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
                    '到点自动执行，不会停下来等人确认。需要确认的动作会跳过，危险命令由策略层拦下。',
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

  /// 条件那一块：树上几条判断、几组判断，都在这里改。
  Widget _conditionEditor() {
    final RuleNode? root = _condition;
    if (root == null) {
      return _addButton('加一条条件（不加就到点直接跑）', _addRule);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _nodeEditor(root, null, 1),
        // 根上只有一条时，还得有地方接着加。
        if (!root.isGroup)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _addButton('再加一条', _addRule),
              _addButton('加一组', _addGroup),
            ],
          ),
      ],
    );
  }

  /// 一层最多套这么深，再深就不好点了。
  static const int _maxDepth = 3;

  Widget _nodeEditor(RuleNode node, RuleNode? parent, int depth) {
    if (!node.isGroup) return _leafRow(node, parent);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(C.radiusSmall),
        border: Border.all(color: C.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _chip('全部满足', node.logic == RuleLogic.all,
                  () => setState(() => node.logic = RuleLogic.all)),
              const SizedBox(width: 8),
              _chip('满足一条', node.logic == RuleLogic.any,
                  () => setState(() => node.logic = RuleLogic.any)),
              const Spacer(),
              if (parent != null)
                GestureDetector(
                  onTap: () => _removeNode(node, parent),
                  child: const SizedBox(
                    width: 26,
                    height: 26,
                    child: Icon(Icons.close, size: 14, color: C.grey2),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final RuleNode child in node.children)
            _nodeEditor(child, node, depth + 1),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _addButton('加一条', () => _addRuleTo(node)),
              if (depth < _maxDepth) _addButton('加一组', () => _addGroupTo(node)),
            ],
          ),
        ],
      ),
    );
  }

  /// 一条判断：指标、比法、数值。
  Widget _leafRow(RuleNode node, RuleNode? parent) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: C.paper2,
        borderRadius: BorderRadius.circular(C.radiusSmall),
        border: Border.all(color: C.rule2),
      ),
      child: Row(
        children: <Widget>[
          _menu<RuleMetric>(
            value: node.rule!.metric,
            items: RuleMetric.values,
            label: (RuleMetric m) => kRuleMetricNames[m]!,
            onPick: (RuleMetric m) => setState(() => node.rule = TaskRule(
                metric: m, op: node.rule!.op, value: node.rule!.value)),
          ),
          const SizedBox(width: 8),
          _menu<RuleOp>(
            value: node.rule!.op,
            items: RuleOp.values,
            label: (RuleOp o) => kRuleOpNames[o]!,
            onPick: (RuleOp o) => setState(() => node.rule = TaskRule(
                metric: node.rule!.metric, op: o, value: node.rule!.value)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _ctlOf(node),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: C.mono.copyWith(fontSize: 13.5),
              decoration: const InputDecoration(hintText: '90', isDense: true),
              onChanged: (String text) {
                final double? v = double.tryParse(text.trim());
                if (v == null) return;
                setState(() => node.rule = TaskRule(
                    metric: node.rule!.metric, op: node.rule!.op, value: v));
              },
            ),
          ),
          GestureDetector(
            onTap: () => _removeNode(node, parent),
            child: const SizedBox(
              width: 30,
              height: 30,
              child: Icon(Icons.close, size: 15, color: C.grey2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addButton(String label, VoidCallback tap) {
    return GestureDetector(
      onTap: tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(C.radiusSmall),
          border: Border.all(color: C.rule2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.add, size: 15, color: C.blue),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12, color: C.blue)),
          ],
        ),
      ),
    );
  }

  TextEditingController _ctlOf(RuleNode leaf) {
    final TextEditingController? have = _values[leaf];
    if (have != null) return have;
    final TextEditingController made =
        TextEditingController(text: ruleNumber(leaf.rule?.value ?? 0));
    _values[leaf] = made;
    return made;
  }

  void _addRule() => setState(() => _attach(RuleNode.rule(
      TaskRule(metric: RuleMetric.disk, value: 90))));

  void _addRuleTo(RuleNode group) => setState(() => group.children
      .add(RuleNode.rule(TaskRule(metric: RuleMetric.disk, value: 90))));

  void _addGroupTo(RuleNode group) => setState(() => group.children.add(
      RuleNode.group(logic: RuleLogic.any, children: <RuleNode>[
        RuleNode.rule(TaskRule(metric: RuleMetric.cpu, value: 80)),
      ])));

  /// 根上的「加一组」：整棵树变成一组，新来的那一组并进去。
  void _addGroup() => setState(() => _attach(RuleNode.group(
        logic: RuleLogic.any,
        children: <RuleNode>[
          RuleNode.rule(TaskRule(metric: RuleMetric.cpu, value: 80)),
        ],
      )));

  /// 往根上加一个节点：没有根就它当根，根是一组就并进去，根只有一条就包成一组。
  void _attach(RuleNode node) {
    final RuleNode? root = _condition;
    if (root == null) {
      _condition = node;
      return;
    }
    if (root.isGroup) {
      root.children.add(node);
      return;
    }
    _condition = RuleNode.group(children: <RuleNode>[root, node]);
  }

  void _removeNode(RuleNode node, RuleNode? parent) {
    setState(() {
      _dropControllers(node);
      if (parent == null) {
        _condition = null;
        return;
      }
      parent.children.remove(node);
      _prune();
    });
  }

  void _dropControllers(RuleNode node) {
    _values.remove(node)?.dispose();
    for (final RuleNode child in node.children) {
      _dropControllers(child);
    }
  }

  /// 删空了的那一组顺手收掉，省得界面上留一个空框。
  void _prune() {
    final RuleNode? root = _condition;
    if (root == null) return;
    _pruneNode(root);
    if (root.isGroup && root.children.isEmpty) _condition = null;
  }

  void _pruneNode(RuleNode node) {
    if (!node.isGroup) return;
    for (final RuleNode child in List<RuleNode>.of(node.children)) {
      _pruneNode(child);
    }
    node.children.removeWhere((RuleNode c) => c.isGroup && c.children.isEmpty);
  }

  /// 存之前把每个数字收一遍。哪个填得不对就回一句话。
  Object? _treeForSave() {
    final RuleNode? root = _condition;
    if (root == null) return null;
    for (final RuleNode leaf in _leavesOf(root)) {
      final double? value = double.tryParse(_ctlOf(leaf).text.trim());
      if (value == null) return '条件里的数要填一个数字。';
      leaf.rule =
          TaskRule(metric: leaf.rule!.metric, op: leaf.rule!.op, value: value);
    }
    return root.deepCopy().collapse();
  }

  List<RuleNode> _leavesOf(RuleNode node) => node.isGroup
      ? <RuleNode>[for (final RuleNode c in node.children) ..._leavesOf(c)]
      : <RuleNode>[node];

  /// 一个只有几个选项的小下拉，选完就换那一格的字。
  Widget _menu<T>({
    required T value,
    required List<T> items,
    required String Function(T) label,
    required void Function(T) onPick,
  }) {
    return PopupMenuButton<T>(
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      onSelected: onPick,
      itemBuilder: (BuildContext ctx) => <PopupMenuEntry<T>>[
        for (final T item in items)
          PopupMenuItem<T>(
            value: item,
            height: 40,
            child: Text(label(item),
                style: TextStyle(fontSize: 13, color: item == value ? C.blue : C.ink)),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: C.paper2,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(label(value), style: const TextStyle(fontSize: 12.5, color: C.ink)),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 13, color: C.grey2),
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
    final String shown = conditionTextOf(_condition);
    final String gate = shown.isEmpty ? '' : ' · 满足 $shown 才跑';
    if (!_enabled) return '${probe.when}$gate · 已停用';
    if (next == null) return '${probe.when}$gate · 时间已经过去了';
    return '${probe.when}$gate · 下次 ${stampText(next, now: now)}';
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

/// 新建或改一条资源监听。阈值只看一个数，超了或者低于就发通知。
class _WatchEditorPage extends StatefulWidget {
  const _WatchEditorPage({
    required this.watch,
    required this.hosts,
    required this.store,
  });

  final WatchTask? watch;
  final HostStore hosts;
  final WatchStore store;

  @override
  State<_WatchEditorPage> createState() => _WatchEditorPageState();
}

class _WatchEditorPageState extends State<_WatchEditorPage> {
  late final TextEditingController _title;
  late final TextEditingController _threshold;
  late String _hostId;
  late WatchKind _kind;
  late WatchMetric _metric;
  late bool _above;
  late int _window;
  late int _interval;
  late int _cooldown;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    final WatchTask? w = widget.watch;
    final List<HostEntry> hosts = widget.hosts.hosts;
    _title = TextEditingController(text: w?.title ?? '');
    _threshold = TextEditingController(
        text: w == null ? '90' : WatchTask.numberText(w.threshold));
    _hostId = w?.hostId ?? (hosts.isEmpty ? '' : hosts.first.id);
    _kind = w?.kind ?? WatchKind.metric;
    _metric = w?.metric ?? WatchMetric.disk;
    _above = w?.above ?? true;
    _window = w?.windowMinutes ?? 10;
    _interval = w?.intervalMinutes ?? 5;
    _cooldown = w?.cooldownMinutes ?? 30;
    _enabled = w?.enabled ?? true;
  }

  @override
  void dispose() {
    _title.dispose();
    _threshold.dispose();
    super.dispose();
  }

  bool get _isNew => widget.watch == null;

  Future<void> _save() async {
    if (_hostId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先选一台主机。监听要盯具体的机器。')),
      );
      return;
    }
    final double? threshold = double.tryParse(_threshold.text.trim());
    if (threshold == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('阈值写个数字。')),
      );
      return;
    }
    final HostEntry? host = widget.hosts.byId(_hostId);
    final WatchTask watch = widget.watch ??
        WatchTask(
          id: WatchStore.newId(),
          title: '',
          hostId: _hostId,
        );
    if (_title.text.trim().isEmpty) {
      final String base = host == null ? '监听' : host.name;
      switch (_kind) {
        case WatchKind.metric:
          watch.title = '$base ${kWatchNames[_metric]}';
        case WatchKind.loginFail:
          watch.title = '$base 失败登录';
        case WatchKind.loginNew:
          watch.title = '$base 新 IP 登录';
      }
    } else {
      watch.title = _title.text.trim();
    }
    watch.hostId = _hostId;
    watch.kind = _kind;
    watch.metric = _metric;
    watch.above = _above;
    watch.windowMinutes = _window;
    watch.threshold = threshold;
    watch.intervalMinutes = _interval;
    watch.cooldownMinutes = _cooldown;
    watch.enabled = _enabled;
    if (_enabled) {
      watch.scheduleFrom(DateTime.now());
    } else {
      watch.nextAt = null;
    }
    await widget.store.upsert(watch);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final WatchTask? watch = widget.watch;
    if (watch == null) return;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('删掉这条监听？', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text('「${watch.title}」和它的读数记录会一起删掉。',
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
    await widget.store.remove(watch.id);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  String get _preview {
    final WatchTask probe = WatchTask(
      id: 'probe',
      title: 'probe',
      hostId: _hostId,
      kind: _kind,
      metric: _metric,
      above: _above,
      threshold: double.tryParse(_threshold.text.trim()) ?? 0,
      windowMinutes: _window,
      intervalMinutes: _interval,
      cooldownMinutes: _cooldown,
    );
    if (!_enabled) return '${probe.when} · 已停用';
    final DateTime at = DateTime.now().add(Duration(minutes: probe.intervalStep));
    return '${probe.when} · 下次 ${stampText(at)}';
  }

  @override
  Widget build(BuildContext context) {
    final List<HostEntry> hosts = widget.hosts.hosts;
    final WatchTask? editing = widget.watch;
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
                      _isNew ? '新监听' : '改监听',
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
                  RuleField(controller: _title, label: '名字', hint: '磁盘快满了'),
                  const SectionLabel('盯哪一台'),
                  const SizedBox(height: 8),
                  if (hosts.isEmpty)
                    const Text('主机列表还是空的，先去主机页加一台。',
                        style: TextStyle(fontSize: 12.5, color: C.body, height: 1.6))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final HostEntry h in hosts)
                          _chip(h.name, _hostId == h.id, () => setState(() => _hostId = h.id)),
                      ],
                    ),
                  const SizedBox(height: 22),
                  const SectionLabel('看什么'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final WatchKind k in WatchKind.values)
                        _chip(kWatchKindNames[k] ?? k.name, _kind == k,
                            () => setState(() => _kind = k)),
                    ],
                  ),
                  if (_kind == WatchKind.metric) ...<Widget>[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final WatchMetric m in WatchMetric.values)
                          _chip(kWatchNames[m] ?? m.name, _metric == m,
                              () => setState(() => _metric = m)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _chip('超过', _above, () => setState(() => _above = true)),
                        _chip('低于', !_above, () => setState(() => _above = false)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    RuleField(
                      controller: _threshold,
                      label: _metric == WatchMetric.load ? '阈值（1 分钟负载）' : '阈值（百分比）',
                      keyboard: TextInputType.number,
                      hint: _metric == WatchMetric.load ? '4.0' : '90',
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                  if (_kind == WatchKind.loginFail) ...<Widget>[
                    const SizedBox(height: 14),
                    RuleField(
                      controller: _threshold,
                      label: '失败次数到多少算异常',
                      keyboard: TextInputType.number,
                      hint: '10',
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final int m in <int>[5, 10, 30, 60])
                          _chip('$m 分钟内', _window == m,
                              () => setState(() => _window = m)),
                      ],
                    ),
                  ],
                  if (_kind == WatchKind.loginNew) ...<Widget>[
                    const SizedBox(height: 12),
                    const Text(
                      '记住已有的登录来源；首次出现的来源登录时提醒。第一次读取会先记录当前来源，之后才认得出新的。',
                      style: TextStyle(fontSize: 11.5, color: C.grey, height: 1.7),
                    ),
                  ],
                  const SectionLabel('多久读一次'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final int m in <int>[1, 5, 15, 30, 60])
                        _chip(_minutes(m), _interval == m, () => setState(() => _interval = m)),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const SectionLabel('提醒过之后歇多久'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final int m in <int>[30, 120, 360, 1440])
                        _chip(_minutes(m), _cooldown == m, () => setState(() => _cooldown = m)),
                    ],
                  ),
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
                              Text(_preview, style: C.monoSmall.copyWith(color: C.blue)),
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
                  const SizedBox(height: 14),
                  const Text(
                    '到点读一次 /proc，过线直接推一条通知到手机。这一路不叫模型，也不花 token。',
                    style: TextStyle(fontSize: 11.5, color: C.grey, height: 1.7),
                  ),
                  if (editing != null && editing.hits.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 22),
                    const SectionLabel('最近读数'),
                    const SizedBox(height: 8),
                    for (final WatchHit hit in editing.hits)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: <Widget>[
                            SizedBox(
                              width: 96,
                              child: Text(hit.stamp, style: C.monoSmall),
                            ),
                            Expanded(
                              child: Text(
                                hit.error.isNotEmpty
                                    ? '读不到：${hit.error}'
                                    : '${editing.valueText(hit.value ?? 0)}'
                                        '${hit.fired ? ' · 已提醒' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: C.monoSmall.copyWith(
                                  color: hit.error.isNotEmpty
                                      ? const Color(0xFFD7443E)
                                      : (hit.fired ? C.blue : C.ink),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
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
                        child: const Text('删掉这条监听'),
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

  static String _minutes(int m) {
    if (m < 60) return '$m 分钟';
    if (m % 60 == 0) {
      final int h = m ~/ 60;
      return h >= 24 ? '${h ~/ 24} 天' : '$h 小时';
    }
    return '$m 分钟';
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
