import 'dart:async';

import 'package:flutter/material.dart';

import '../core/monitor.dart';
import '../data/hosts.dart';
import '../data/monitor.dart';
import '../tools/ssh_tools.dart';
import 'components.dart';
import 'theme.dart';

/// 主机资源监看：每台一张卡，CPU、内存、交换、磁盘、网络、负载。
///
/// 按设定的间隔重读一遍，关掉页面就不再读。
class ResourcesPage extends StatefulWidget {
  const ResourcesPage({super.key, required this.hosts, required this.pool});

  final HostStore hosts;
  final SshPool pool;

  @override
  State<ResourcesPage> createState() => _ResourcesPageState();
}

class _ResourcesPageState extends State<ResourcesPage> {
  late final HostProbe _probe = HostProbe(widget.pool);
  final Map<String, HostReading> _rows = <String, HostReading>{};
  Timer? _timer;
  int _every = 5;

  @override
  void initState() {
    super.initState();
    _restartTimer();
    _pollAll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (_every <= 0) return;
    _timer = Timer.periodic(Duration(seconds: _every), (_) => _pollAll());
  }

  void _pollAll() {
    for (final HostEntry h in widget.hosts.hosts) {
      unawaited(_read(h));
    }
  }

  Future<void> _read(HostEntry host) async {
    final HostReading row = _rows[host.id] ??= HostReading(host: host);
    if (row.loading) return;
    row.loading = true;
    if (mounted) setState(() {});
    final Stopwatch watch = Stopwatch()..start();
    try {
      final HostMetrics next = await _probe.read(host);
      final HostMetrics? before = row.metrics;
      watch.stop();
      double? rx;
      double? tx;
      if (before != null) {
        final Duration span = next.at.difference(before.at);
        rx = rateBetween(next.netRx, before.netRx, span);
        tx = rateBetween(next.netTx, before.netTx, span);
      }
      if (!mounted) return;
      setState(() {
        row.metrics = next;
        row.error = '';
        row.ms = watch.elapsedMilliseconds;
        row.loading = false;
        row.done = true;
        row.rxRate = rx;
        row.txRate = tx;
      });
    } catch (e) {
      watch.stop();
      if (!mounted) return;
      setState(() {
        row.error = _explain(e);
        row.ms = watch.elapsedMilliseconds;
        row.loading = false;
        row.done = true;
        row.metrics = null;
        row.rxRate = null;
        row.txRate = null;
      });
    }
  }

  /// 连接失败的原文往往很长，摘一句能看懂的。
  String _explain(Object e) {
    final String text = '$e'.replaceFirst('Exception: ', '').replaceFirst('StateError: ', '');
    final String key = widget.pool.lastKeyError;
    if (key.isNotEmpty) return '$key $text';
    return text.length > 220 ? '${text.substring(0, 220)}…' : text;
  }

  int get _online {
    int n = 0;
    for (final HostReading r in _rows.values) {
      if (r.online) n += 1;
    }
    return n;
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
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: const BoxDecoration(
                color: C.card,
                border: Border(bottom: BorderSide(color: C.rule)),
              ),
              child: Row(
                children: <Widget>[
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, size: 19, color: C.ink),
                  ),
                  const Text('资源监看',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Text('在线 $_online/${hosts.length}', style: C.monoSmall),
                  const Spacer(),
                  IconButton(
                    onPressed: _pollAll,
                    icon: const Icon(Icons.refresh, size: 18, color: C.grey),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: <Widget>[
                  const Text('多久读一次', style: TextStyle(fontSize: 11.5, color: C.grey)),
                  const SizedBox(width: 10),
                  for (final int s in <int>[5, 15, 0]) ...<Widget>[
                    _chip(s == 0 ? '暂停' : '$s 秒', _every == s, () {
                      setState(() => _every = s);
                      _restartTimer();
                    }),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            Expanded(
              child: hosts.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.fromLTRB(20, 26, 20, 0),
                      child: Text('还没有主机。先在主机页添加一台。',
                          style: TextStyle(fontSize: 13.5, height: 1.6, color: C.body)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                      itemCount: hosts.length,
                      itemBuilder: (BuildContext context, int i) {
                        final HostEntry h = hosts[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _card(_rows[h.id] ?? HostReading(host: h)),
                        );
                      },
                    ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: const Text(
                '读取 /proc 与 df，只读，不需要 root。离开本页后停止读取，不在后台保持连接。',
                style: TextStyle(fontSize: 11, color: C.grey, height: 1.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool on, VoidCallback tap) {
    return GestureDetector(
      onTap: tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on ? C.blueSoft : C.card,
          borderRadius: BorderRadius.circular(C.radiusSmall),
          border: Border.all(color: on ? C.blue : C.rule2),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 11.5,
              color: on ? C.blue : C.ink,
              fontWeight: on ? FontWeight.w600 : FontWeight.w400,
            )),
      ),
    );
  }

  Widget _card(HostReading row) {
    final HostMetrics? m = row.metrics;
    return CardBox(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(row.host.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              ),
              _state(row),
            ],
          ),
          const SizedBox(height: 4),
          Text(row.host.address,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: C.monoSmall),
          if (row.error.isNotEmpty) ...<Widget>[
            const SizedBox(height: 9),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: C.paper2,
                borderRadius: BorderRadius.circular(C.radiusSmall),
              ),
              child: Text(row.error,
                  style: C.output.copyWith(fontSize: 11.5, height: 1.55)),
            ),
          ],
          if (m != null) ...<Widget>[
            const SizedBox(height: 10),
            _bar('CPU',
                m.cpuPercent == null ? '—' : '${m.cpuPercent!.round()}%', m.cpuPercent),
            _bar(
              '内存',
              m.memPercent == null
                  ? '—'
                  : '${HostMetrics.size(m.memUsedKb)} / ${HostMetrics.size(m.memTotalKb)}'
                      ' · ${m.memPercent!.round()}%',
              m.memPercent,
            ),
            if (m.swapTotalKb > 0)
              _bar(
                '交换',
                '${HostMetrics.size(m.swapUsedKb)} / ${HostMetrics.size(m.swapTotalKb)}'
                    ' · ${m.swapPercent?.round() ?? 0}%',
                m.swapPercent,
              ),
            _bar(
              '磁盘',
              m.diskPercent == null
                  ? '—'
                  : '${HostMetrics.size(m.diskUsedKb)} / ${HostMetrics.size(m.diskTotalKb)}'
                      ' · ${m.diskPercent!.round()}%',
              m.diskPercent,
            ),
            const SizedBox(height: 8),
            const RuleLine(),
            const SizedBox(height: 8),
            _line('负载',
                '${m.load1.toStringAsFixed(2)} / ${m.load5.toStringAsFixed(2)} / '
                '${m.load15.toStringAsFixed(2)} · ${m.cores} 核'),
            _line('网络',
                '↓ ${HostMetrics.rate(row.rxRate ?? 0)}  ↑ ${HostMetrics.rate(row.txRate ?? 0)}'),
            _line('累计',
                '↓ ${HostMetrics.size(m.netRx ~/ 1024)}  ↑ ${HostMetrics.size(m.netTx ~/ 1024)}'),
            _line('运行', HostMetrics.duration(m.uptimeSeconds)),
            _line('内核', m.os.isEmpty ? '—' : m.os),
          ],
        ],
      ),
    );
  }

  Widget _state(HostReading row) {
    final String text = row.loading
        ? '读数'
        : row.error.isNotEmpty
            ? '连不上'
            : row.done
                ? '${row.ms} ms'
                : '等着';
    final Color fg = row.error.isNotEmpty ? const Color(0xFFD7443E) : C.blue;
    final Color bg = row.error.isNotEmpty ? const Color(0xFFFBEDEC) : C.blueSoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: C.monoSmall.copyWith(fontSize: 10, color: fg, height: 1.4)),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 40,
            child: Text(label, style: const TextStyle(fontSize: 11.5, color: C.grey)),
          ),
          Expanded(
            child: Text(value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: C.monoSmall.copyWith(color: C.ink, fontSize: 11.5)),
          ),
        ],
      ),
    );
  }

  /// 一行标签、一行读数、底下一条细线。用得越满线越长，九成以上变红。
  Widget _bar(String label, String value, double? percent) {
    final double v = ((percent ?? 0) / 100).clamp(0.0, 1.0);
    final int lit = (v * 1000).round();
    final Color fill = percent == null
        ? C.rule2
        : (v >= 0.9 ? const Color(0xFFD7443E) : C.blue);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(
                width: 40,
                child: Text(label, style: const TextStyle(fontSize: 11.5, color: C.grey)),
              ),
              Expanded(
                child: Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: C.monoSmall.copyWith(color: C.ink, fontSize: 11.5)),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 4,
              child: Row(
                children: <Widget>[
                  if (lit > 0) Expanded(flex: lit, child: Container(color: fill)),
                  if (lit < 1000)
                    Expanded(flex: 1000 - lit, child: Container(color: C.paper2)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
