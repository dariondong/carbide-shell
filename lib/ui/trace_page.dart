import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/trace.dart';
import 'components.dart';
import 'md_text.dart';
import 'theme.dart';

/// 会话的工具轨迹：这一路上模型问了几次、叫了哪些工具、每次花了多久、回来的是什么。
///
/// 轨迹来自这个对话自己的那份日志（一轮一行 JSON），所以和对话里看到的一步步对得上，
/// 关掉应用再打开也还在。这一轮还在跑的时候，隔两秒自己重读一遍。
class TracePage extends StatefulWidget {
  const TracePage({super.key, required this.file, this.live = false});

  final File file;

  /// 还在跑：最新那个工具调用可能只有「叫了」还没有回来。
  final bool live;

  @override
  State<TracePage> createState() => _TracePageState();
}

class _TracePageState extends State<TracePage> {
  List<TraceEntry> _list = <TraceEntry>[];
  final Set<int> _open = <int>{};
  bool _loading = true;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.live) {
      _ticker = Timer.periodic(const Duration(seconds: 2), (Timer t) => _load());
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final File file = widget.file;
    if (!file.existsSync()) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    String raw = '';
    try {
      raw = await file.readAsString();
    } catch (_) {
      // 读不到就当没有，别把整页弄崩。
    }
    final List<TraceEntry> list = parseJournal(raw);
    if (!mounted) return;
    setState(() {
      _list = list;
      _loading = false;
    });
  }

  int get _calls => _list.where((TraceEntry t) => t.isTool).length;

  int get _turns => _list.where((TraceEntry t) => t.kind == TraceKind.turn).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.paper,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Container(
              height: 56,
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
              decoration: const BoxDecoration(
                color: C.card,
                border: Border(bottom: BorderSide(color: C.rule)),
              ),
              child: Row(
                children: <Widget>[
                  const Text('工具轨迹',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _loading ? '读取中' : '$_calls 步 · $_turns 轮',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: C.monoSmall,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _load,
                    behavior: HitTestBehavior.opaque,
                    child: const SizedBox(
                      width: 34,
                      height: 56,
                      child: Icon(Icons.refresh, size: 18, color: C.grey),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(18, 26, 18, 16),
                      child: Text(
                        _loading
                            ? '正在读这一轮的日志。'
                            : '这个对话还没有跑过工具。模型一旦叫了工具，这里就按时间记下来：第几步、做了什么、用了多久、回来的是什么。',
                        style: const TextStyle(fontSize: 12.5, height: 1.7, color: C.body),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 26),
                      itemCount: _list.length,
                      itemBuilder: (BuildContext ctx, int i) => _row(i),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(int index) {
    final TraceEntry trace = _list[index];
    switch (trace.kind) {
      case TraceKind.turn:
        return _turnRow(trace);
      case TraceKind.llm:
        return _llmRow(trace);
      case TraceKind.tool:
        return _toolRow(index, trace);
      case TraceKind.note:
        return _noteRow(trace);
    }
  }

  Widget _turnRow(TraceEntry trace) {
    final String ask = trace.text.trim().replaceAll('\n', ' ');
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('第 ${trace.turn} 轮', style: C.label),
              const SizedBox(width: 8),
              Text(_clock(trace.at), style: C.monoSmall.copyWith(fontSize: 10.5)),
            ],
          ),
          if (ask.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              ask,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, height: 1.5, color: C.body),
            ),
          ],
        ],
      ),
    );
  }

  Widget _llmRow(TraceEntry trace) {
    final String tokens =
        trace.prompt > 0 ? '${_fmt(trace.prompt)} 进 · ${_fmt(trace.out)} 出' : '';
    final String hit = trace.prompt > 0 && trace.cached > 0
        ? ' · 命中 ${(100 * trace.cached / trace.prompt).round()}%'
        : '';
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 6),
      child: Row(
        children: <Widget>[
          const Icon(Icons.memory, size: 13, color: C.grey2),
          const SizedBox(width: 7),
          Text('模型第 ${trace.step} 步', style: C.monoSmall.copyWith(color: C.grey)),
          if (tokens.isNotEmpty) ...<Widget>[
            const SizedBox(width: 8),
            Expanded(
              child: Text('$tokens$hit',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: C.monoSmall.copyWith(fontSize: 10.5, color: C.grey2)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _toolRow(int index, TraceEntry trace) {
    final bool open = _open.contains(index);
    final String arg = trace.argText;
    final Color dot = !trace.hasResult
        ? C.rule2
        : (trace.ok ? const Color(0xFF3FA96B) : const Color(0xFFD7443E));
    final String right = !trace.hasResult
        ? (widget.live ? '跑着' : '没回来')
        : '${trace.ms > 0 ? '${trace.ms} ms' : '完成'}${trace.ok ? '' : ' · 失败'}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CardBox(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            GestureDetector(
              onTap: trace.output.isEmpty
                  ? null
                  : () => setState(() {
                        if (open) {
                          _open.remove(index);
                        } else {
                          _open.add(index);
                        }
                      }),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: <Widget>[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(trace.name,
                      style: C.monoSmall.copyWith(
                          fontSize: 11, fontWeight: FontWeight.w600, color: C.ink)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      arg.isEmpty ? trace.summary : arg,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: C.monoSmall.copyWith(fontSize: 11, color: C.grey),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(right,
                      style: C.monoSmall.copyWith(fontSize: 10.5, color: C.grey2)),
                  if (trace.output.isNotEmpty)
                    Icon(open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 15, color: C.grey2),
                ],
              ),
            ),
            if (trace.verdictText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 15),
                child: Text(trace.verdictText,
                    style: C.monoSmall.copyWith(fontSize: 10.5, color: C.grey2)),
              ),
            if (open && trace.output.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  color: C.paper2,
                  borderRadius: BorderRadius.circular(C.radiusSmall),
                ),
                child: LinkText(text: trace.output, style: C.output),
              ),
          ],
        ),
      ),
    );
  }

  Widget _noteRow(TraceEntry trace) {
    final String text = trace.text.trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 2, top: 2, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.flag_outlined, size: 13, color: C.grey2),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text.replaceAll('\n', ' '),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, height: 1.6, color: C.grey),
            ),
          ),
        ],
      ),
    );
  }

  static String _clock(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }

  static String _fmt(int n) {
    if (n < 1000) return '$n';
    final double k = n / 1000;
    return '${k.toStringAsFixed(k < 10 ? 1 : 0)}k';
  }
}
