import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import '../core/monitor.dart';
import '../tools/ssh_tools.dart';
import 'hosts.dart';

/// 借现有 SSH 连接去读一台主机的 /proc。失败就把原因原样抛上去。
class HostProbe {
  HostProbe(this.pool);

  final SshPool pool;

  /// 命令里有一个 sleep 1，留够余量。
  static const Duration timeout = Duration(seconds: 15);

  Future<HostMetrics> read(HostEntry host) async {
    final SSHClient client = await pool.connect(host);
    final SSHRunResult result;
    try {
      result = await client.runWithResult(kProbeCommand).timeout(timeout);
    } on TimeoutException {
      await pool.drop(host.id);
      throw StateError('${timeout.inSeconds} 秒没有回音，连接已断开');
    }
    final HostMetrics? metrics = parseMetrics(utf8.decode(result.stdout, allowMalformed: true));
    if (metrics == null) {
      final String err = utf8.decode(result.stderr, allowMalformed: true).trim();
      if (err.isNotEmpty) throw StateError(err.split('\n').first);
      throw StateError('没有读到 /proc，这台可能不是 Linux');
    }
    return metrics;
  }
}

/// 一台主机这一轮的读数，加上花了多久、错在哪。
class HostReading {
  HostReading({required this.host});

  final HostEntry host;
  HostMetrics? metrics;
  String error = '';
  int ms = 0;
  bool loading = false;

  /// 第一次读完之前不写「—」，写「正在读」。
  bool done = false;

  double? rxRate;
  double? txRate;

  bool get online => metrics != null && error.isEmpty;
}
