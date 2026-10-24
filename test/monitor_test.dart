import 'package:carbide_shell/core/monitor.dart';
import 'package:flutter_test/flutter_test.dart';

const String sample = '''
#OS
Linux 6.8.0-45-generic
#UP
264319.77
#LOAD
0.15 0.10 0.05 1/234 5678
#CORES
4
#CPU1
cpu  100000 500 20000 800000 5000 0 2000 0 0 0
#CPU2
cpu  100500 520 20100 800900 5010 0 2000 0 0 0
#MEM
MemTotal:        1965628 kB
MemFree:          102400 kB
MemAvailable:     786432 kB
Buffers:           20480 kB
Cached:           409600 kB
SwapCached:            0 kB
Active:           600000 kB
Inactive:         200000 kB
Unevictable:           0 kB
SwapTotal:       1048576 kB
SwapFree:         524288 kB
#DF
/dev/vda1 41152736 8123456 30941234 21% /
#NET
  eth0: 5000000 1000 0 0 0 0 0 0 2000000 900 0 0 0 0 0 0
    lo: 999999 5 0 0 0 0 0 0 999999 5 0 0 0 0 0 0
#END
''';

void main() {
  group('解析采集输出', () {
    final HostMetrics m = parseMetrics(sample, now: DateTime(2026, 10, 24, 12, 0))!;

    test('系统与运行时长', () {
      expect(m.os, 'Linux 6.8.0-45-generic');
      expect(m.uptimeSeconds, 264319);
      expect(HostMetrics.duration(m.uptimeSeconds), '3 天 1 小时');
    });

    test('负载与核数', () {
      expect(m.load1, 0.15);
      expect(m.load5, 0.10);
      expect(m.load15, 0.05);
      expect(m.cores, 4);
    });

    test('CPU 占用按两次采样之差算', () {
      // total 1530，其中 idle+iowait 910，忙 620
      expect(m.cpuPercent!.toStringAsFixed(1), '40.5');
    });

    test('内存与交换', () {
      expect(m.memTotalKb, 1965628);
      expect(m.memUsedKb, 1965628 - 786432);
      expect(m.memPercent!.toStringAsFixed(1), '60.0');
      expect(m.swapPercent!.toStringAsFixed(1), '50.0');
      expect(HostMetrics.size(m.memTotalKb), '1.87 GB');
    });

    test('磁盘', () {
      expect(m.diskPercent!.round(), 20);
      expect(HostMetrics.size(m.diskTotalKb), '39.2 GB');
    });

    test('网络只算真实网卡，lo 不算', () {
      expect(m.netRx, 5000000);
      expect(m.netTx, 2000000);
    });
  });

  group('缺东西也不炸', () {
    test('老内核没有 MemAvailable', () {
      final HostMetrics m = parseMetrics('''
#MEM
MemTotal:        1000000 kB
MemFree:          100000 kB
Buffers:           50000 kB
Cached:           250000 kB
#END
''')!;
      expect(m.memAvailKb, 400000);
      expect(m.memPercent!.round(), 60);
    });

    test('只有内核', () {
      final HostMetrics m = parseMetrics('#OS\nLinux 5.4.0\n#END\n')!;
      expect(m.os, 'Linux 5.4.0');
      expect(m.cpuPercent, isNull);
      expect(m.diskPercent, isNull);
      expect(m.memPercent, isNull);
    });

    test('不是采集输出就返回 null', () {
      expect(parseMetrics(''), isNull);
      expect(parseMetrics('ssh: connect to host offline\n'), isNull);
    });
  });

  group('单位换算', () {
    test('容量', () {
      expect(HostMetrics.size(0), '0');
      expect(HostMetrics.size(1536), '1.5 MB');
      expect(HostMetrics.size(1965628), '1.87 GB');
      expect(HostMetrics.size(3000000000), '2.79 TB');
    });

    test('时长', () {
      expect(HostMetrics.duration(3 * 86400 + 4 * 3600 + 120), '3 天 4 小时');
      expect(HostMetrics.duration(2 * 3600 + 5 * 60), '2 小时 5 分');
      expect(HostMetrics.duration(46), '46 秒');
      expect(HostMetrics.duration(0), '—');
    });

    test('速率', () {
      expect(HostMetrics.rate(0), '0 B/s');
      expect(HostMetrics.rate(900), '900 B/s');
      expect(HostMetrics.rate(1258291), '1.20 MB/s');
      expect(rateBetween(2048, 1024, const Duration(seconds: 2))!.toStringAsFixed(0), '512');
      expect(rateBetween(10, 100, const Duration(seconds: 2)), isNull);
      expect(rateBetween(10, 5, Duration.zero), isNull);
    });
  });
}
