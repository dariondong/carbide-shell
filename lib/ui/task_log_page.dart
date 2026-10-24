import 'package:flutter/material.dart';

import '../core/schedule.dart';
import '../data/tasks.dart';
import 'components.dart';
import 'theme.dart';

/// 任务日志：所有定时任务跑过的每一轮，按时间倒序摆在一起。
///
/// 每条记着原定时刻、成没成、条件读数、模型的最后一段话。跑失败和条件不够而没跑的
/// 也能在这里挑出来看。
class TaskLogPage extends StatefulWidget {
  const TaskLogPage({super.key, required this.tasks});

  final TaskStore tasks;

  @override
  State<TaskLogPage> createState() => _TaskLogPageState();
}

/// 一条日志：哪条任务、哪一轮。
class _Entry {
  _Entry(this.task, this.run);

  final ScheduledTask task;
  final TaskRun run;
}

enum _Filter { all, failed, skipped }

class _TaskLogPageState extends State<TaskLogPage> {
  _Filter _filter = _Filter.all;
  final Set<String> _open = <String>{};

  List<_Entry> get _entries {
    final List<_Entry> out = <_Entry>[];
    for (final ScheduledTask task in widget.tasks.all) {
      for (final TaskRun run in task.runs) {
        final bool hidden = switch (_filter) {
          _Filter.all => false,
          _Filter.failed => run.ok || run.skipped || run.missed,
          _Filter.skipped => !run.skipped && !run.missed,
        };
        if (hidden) continue;
        out.add(_Entry(task, run));
      }
    }
    out.sort((_Entry a, _Entry b) => b.run.at.compareTo(a.run.at));
    return out;
  }

  String _key(_Entry e) => '${e.task.id}@${e.run.at.toIso8601String()}';

  String _statusText(TaskRun run) {
    if (run.missed) return '错过';
    if (run.skipped) return '条件不够';
    return run.ok ? '完成' : '失败';
  }

  Color _statusColor(TaskRun run) {
    if (run.missed || run.skipped) return C.grey;
    return run.ok ? C.blue : const Color(0xFFD7443E);
  }

  @override
  Widget build(BuildContext context) {
    final List<_Entry> list = _entries;
    return Scaffold(
      backgroundColor: C.paper,
      body: SafeArea(
        child: Column(
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
                  const Text('任务日志',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
                  const SizedBox(width: 8),
                  Text('${list.length} 条', style: C.monoSmall),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: <Widget>[
                  _chip('全部', _Filter.all),
                  const SizedBox(width: 8),
                  _chip('失败', _Filter.failed),
                  const SizedBox(width: 8),
                  _chip('跳过', _Filter.skipped),
                ],
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                      child: Text(
                        _filter == _Filter.all
                            ? '还没有运行记录。任务跑过一轮之后，这里按时间记下来。'
                            : '这个分类里没有记录。',
                        style: const TextStyle(
                            fontSize: 12.5, height: 1.7, color: C.body),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: list.length,
                      itemBuilder: (BuildContext ctx, int i) => _row(list[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, _Filter value) {
    final bool on = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: on ? C.blue : C.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: on ? C.blue : C.rule2),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 12, color: on ? Colors.white : C.ink)),
      ),
    );
  }

  Widget _row(_Entry entry) {
    final TaskRun run = entry.run;
    final String key = _key(entry);
    final bool open = _open.contains(key);
    final String note = run.note.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => setState(() {
          if (open) {
            _open.remove(key);
          } else {
            _open.add(key);
          }
        }),
        child: CardBox(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: _statusColor(run),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      entry.task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_statusText(run),
                      style: C.monoSmall.copyWith(color: _statusColor(run))),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                '${run.stamp}'
                '${run.late ? ' · 补跑' : ''}'
                '${run.steps > 0 ? ' · ${run.steps} 步' : ''}'
                '${run.tokens > 0 ? ' · ${run.tokens} tok' : ''}',
                style: C.monoSmall,
              ),
              if (run.gate.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text('条件 ${run.gate}',
                    style: C.monoSmall.copyWith(color: C.grey)),
              ],
              if (note.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  note,
                  maxLines: open ? 200 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, height: 1.6, color: C.body),
                ),
              ],
              if (open && run.answer.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                const RuleLine(),
                const SizedBox(height: 8),
                Text(
                  run.answer.trim(),
                  style: const TextStyle(fontSize: 12.5, height: 1.65, color: C.body),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
