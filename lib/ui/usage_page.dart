import 'package:flutter/material.dart';

import '../core/usage.dart';
import '../data/usage.dart';
import 'components.dart';
import 'theme.dart';

/// 用量：花掉多少 token、命中多少缓存，按天和按模型各看一眼。
class UsagePage extends StatefulWidget {
  const UsagePage({super.key, required this.usage});

  final UsageStore usage;

  @override
  State<UsagePage> createState() => _UsagePageState();
}

class _UsagePageState extends State<UsagePage> {
  /// 0 = 全部，其余是天数。
  int _days = 7;

  List<UsageEntry> get _entries => _days <= 0
      ? widget.usage.all
      : usageSince(widget.usage.all, usageFrom(_days));

  Future<void> _clear() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('清空用量账本？',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text('只删这些数字，对话都还在。清掉之后累计从头算。',
            style: TextStyle(fontSize: 13, height: 1.6)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消', style: TextStyle(fontSize: 13, color: C.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空', style: TextStyle(fontSize: 13, color: Color(0xFFD7443E))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.usage.clear();
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final List<UsageEntry> entries = _entries;
    final UsageTotals totals = UsageTotals()..addAll(entries);
    final List<UsageModelRow> models = usageByModel(entries);
    final List<UsageDayRow> days = usageLastDays(widget.usage.all, 14);
    int peak = 0;
    for (final UsageDayRow d in days) {
      if (d.totals.total > peak) peak = d.totals.total;
    }
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
                    icon: const Icon(Icons.arrow_back_ios_new, size: 17, color: C.ink),
                  ),
                  const Expanded(
                    child: Text('用量',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                  TextButton(
                    onPressed: totals.isEmpty ? null : _clear,
                    style: TextButton.styleFrom(
                      foregroundColor: C.grey,
                      minimumSize: const Size(0, 36),
                      textStyle: const TextStyle(fontSize: 12.5),
                    ),
                    child: const Text('清空'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
                children: <Widget>[
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      for (final int days in <int>[1, 7, 30, 0])
                        _chip(_rangeName(days), _days == days,
                            () => setState(() => _days = days)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  CardBox(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            _cell('对话轮数', '${totals.turns}'),
                            _cell('输入 token', usageText(totals.prompt)),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: RuleLine(),
                        ),
                        Row(
                          children: <Widget>[
                            _cell('输出 token', usageText(totals.completion)),
                            _cell('缓存命中',
                                usageRate(totals.cacheRate, cached: totals.cached)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const SectionLabel('按模型'),
                  const SizedBox(height: 8),
                  if (models.isEmpty)
                    const Text('这段时间还没有记录。',
                        style: TextStyle(fontSize: 12.5, color: C.body, height: 1.65))
                  else
                    CardBox(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: <Widget>[
                          for (int i = 0; i < models.length; i += 1) ...<Widget>[
                            if (i > 0) const RuleLine(),
                            _modelRow(models[i]),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 22),
                  const SectionLabel('最近 14 天'),
                  const SizedBox(height: 8),
                  CardBox(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                    child: Column(
                      children: <Widget>[
                        SizedBox(
                          height: 64,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: <Widget>[
                              for (final UsageDayRow d in days)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 2),
                                    child: Container(
                                      height: peak <= 0
                                          ? 3
                                          : 3 + 58 * (d.totals.total / peak),
                                      decoration: BoxDecoration(
                                        color: d.totals.total <= 0 ? C.rule2 : C.blue,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: <Widget>[
                            Text(days.isEmpty ? '' : days.first.day.substring(5),
                                style: C.monoSmall.copyWith(fontSize: 10, color: C.grey2)),
                            const Spacer(),
                            Text('今天',
                                style: C.monoSmall.copyWith(fontSize: 10, color: C.grey2)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '一轮对话结束记一笔，只记 token 数，不记内容。命中率是输入里由服务端缓存供上的比例，'
                    '模型没报缓存就是「—」。',
                    style: TextStyle(fontSize: 11.5, color: C.grey, height: 1.7),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modelRow(UsageModelRow row) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(row.model,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: C.ink)),
              ),
              const SizedBox(width: 8),
              Text('${row.totals.turns} 轮',
                  style: C.monoSmall.copyWith(color: C.grey)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '输入 ${usageText(row.totals.prompt)} · 输出 ${usageText(row.totals.completion)}'
            ' · 命中 ${usageRate(row.totals.cacheRate, cached: row.totals.cached)}',
            style: C.monoSmall.copyWith(color: C.grey2),
          ),
        ],
      ),
    );
  }

  Widget _cell(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: const TextStyle(fontSize: 11.5, color: C.grey)),
          const SizedBox(height: 5),
          Text(value,
              style: const TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w700, color: C.ink, height: 1.1)),
        ],
      ),
    );
  }

  static String _rangeName(int days) {
    switch (days) {
      case 1:
        return '今天';
      case 7:
        return '7 天';
      case 30:
        return '30 天';
      default:
        return '全部';
    }
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
