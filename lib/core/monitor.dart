/// 读一台 Linux 主机的基本资源：CPU、内存、交换、磁盘、负载、网络、运行时长。
///
/// 采集侧发一条一次性命令，这里只负责把它的输出拆成数字。
/// 纯 Dart：不 import Flutter，也不碰网络，解析可以单独测。
library;

/// 采集命令。一条连接、一次往返，`sleep 1` 是为了拿两次 /proc/stat 算 CPU 占用。
///
/// 只读 /proc 和 df，不需要 root。有的机器没有 nproc，就数 cpuinfo 里的 processor。
const String kProbeCommand = r'''
LC_ALL=C
echo '#OS'; uname -sr 2>/dev/null
echo '#UP'; cut -d' ' -f1 /proc/uptime 2>/dev/null
echo '#LOAD'; cut -d' ' -f1-3 /proc/loadavg 2>/dev/null
echo '#CORES'; nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null
echo '#CPU1'; head -n1 /proc/stat 2>/dev/null
sleep 1
echo '#CPU2'; head -n1 /proc/stat 2>/dev/null
echo '#MEM'; head -n 20 /proc/meminfo 2>/dev/null
echo '#DF'; df -kP / 2>/dev/null | tail -n1
echo '#NET'; cat /proc/net/dev 2>/dev/null | tail -n +3
echo '#END'
''';

/// 一台主机这一轮读到的数字。缺什么就是 null，界面写「—」。
class HostMetrics {
  const HostMetrics({
    required this.at,
    this.os = '',
    this.uptimeSeconds = 0,
    this.load1 = 0,
    this.load5 = 0,
    this.load15 = 0,
    this.cores = 0,
    this.cpuPercent,
    this.memTotalKb = 0,
    this.memAvailKb = 0,
    this.swapTotalKb = 0,
    this.swapFreeKb = 0,
    this.diskTotalKb = 0,
    this.diskUsedKb = 0,
    this.netRx = 0,
    this.netTx = 0,
  });

  final DateTime at;
  final String os;
  final int uptimeSeconds;
  final double load1;
  final double load5;
  final double load15;
  final int cores;

  /// 两次 /proc/stat 之间算出来的占用，0 到 100。读不到就是 null。
  final double? cpuPercent;

  final int memTotalKb;
  final int memAvailKb;
  final int swapTotalKb;
  final int swapFreeKb;
  final int diskTotalKb;
  final int diskUsedKb;

  /// 网卡累计字节，速率要靠前后两次自己算。
  final int netRx;
  final int netTx;

  int get memUsedKb {
    final int used = memTotalKb - memAvailKb;
    return used < 0 ? 0 : used;
  }

  int get swapUsedKb {
    final int used = swapTotalKb - swapFreeKb;
    return used < 0 ? 0 : used;
  }

  /// 0 到 100，读不到总量就是 null。
  double? percentOf(int used, int total) {
    if (total <= 0) return null;
    final double p = used * 100 / total;
    return p < 0 ? 0 : (p > 100 ? 100 : p);
  }

  double? get memPercent => percentOf(memUsedKb, memTotalKb);

  double? get swapPercent => swapTotalKb <= 0 ? null : percentOf(swapUsedKb, swapTotalKb);

  double? get diskPercent => percentOf(diskUsedKb, diskTotalKb);

  /// `32.4 GB`：容量都按 1024 进位，和 df、free 的口径一致。
  static String size(int kb) {
    if (kb <= 0) return '0';
    final double mb = kb / 1024;
    if (mb < 1) return '$kb KB';
    if (mb < 1024) return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
    final double gb = mb / 1024;
    if (gb < 1024) return '${gb.toStringAsFixed(gb < 10 ? 2 : 1)} GB';
    return '${(gb / 1024).toStringAsFixed(2)} TB';
  }

  /// `3 天 4 小时`、`2 小时 5 分`、`46 秒`。
  static String duration(int seconds) {
    if (seconds <= 0) return '—';
    final int days = seconds ~/ 86400;
    final int hours = (seconds % 86400) ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;
    if (days > 0) return hours > 0 ? '$days 天 $hours 小时' : '$days 天';
    if (hours > 0) return minutes > 0 ? '$hours 小时 $minutes 分' : '$hours 小时';
    if (minutes > 0) return '$minutes 分';
    return '$seconds 秒';
  }

  /// 每秒多少字节写成 `1.2 MB/s`。
  static String rate(double bytesPerSecond) {
    if (bytesPerSecond <= 0) return '0 B/s';
    if (bytesPerSecond < 1024) return '${bytesPerSecond.toStringAsFixed(0)} B/s';
    final double kb = bytesPerSecond / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB/s';
    final double mb = kb / 1024;
    return '${mb.toStringAsFixed(mb < 10 ? 2 : 1)} MB/s';
  }
}

/// 把一条采集命令的输出拆成数字。认不出的那几段就留空。
HostMetrics? parseMetrics(String raw, {DateTime? now}) {
  final Map<String, List<String>> blocks = <String, List<String>>{};
  String? tag;
  for (final String line in raw.split('\n')) {
    final String t = line.trimRight();
    if (t.startsWith('#')) {
      final String name = t.substring(1).trim().toUpperCase();
      if (name == 'END') {
        tag = null;
        continue;
      }
      tag = name;
      blocks[tag] = <String>[];
      continue;
    }
    if (tag != null) blocks[tag]!.add(t);
  }
  if (blocks.isEmpty) return null;

  final List<String> os = blocks['OS'] ?? const <String>[];
  final String kernel = os.isEmpty ? '' : os.first.trim();

  final List<String> up = blocks['UP'] ?? const <String>[];
  final double upSeconds = up.isEmpty ? 0 : (double.tryParse(up.first.trim()) ?? 0);

  final List<String> load = blocks['LOAD'] ?? const <String>[];
  final List<String> loadParts = load.isEmpty ? const <String>[] : load.first.trim().split(RegExp(r'\s+'));
  double pick(int i) => i < loadParts.length ? (double.tryParse(loadParts[i]) ?? 0) : 0;

  final List<String> cores = blocks['CORES'] ?? const <String>[];
  final int coreCount = cores.isEmpty ? 0 : (int.tryParse(cores.first.trim()) ?? 0);

  // 内存与交换
  int memTotal = 0;
  int memFree = 0;
  int memAvail = 0;
  int buffers = 0;
  int cached = 0;
  int swapTotal = 0;
  int swapFree = 0;
  for (final String line in blocks['MEM'] ?? const <String>[]) {
    final int colon = line.indexOf(':');
    if (colon < 0) continue;
    final String key = line.substring(0, colon).trim();
    final List<String> parts = line.substring(colon + 1).trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) continue;
    final int value = int.tryParse(parts.first) ?? 0;
    switch (key) {
      case 'MemTotal':
        memTotal = value;
      case 'MemFree':
        memFree = value;
      case 'MemAvailable':
        memAvail = value;
      case 'Buffers':
        buffers = value;
      case 'Cached':
        cached = value;
      case 'SwapTotal':
        swapTotal = value;
      case 'SwapFree':
        swapFree = value;
    }
  }
  // 老内核没有 MemAvailable，用 Free + Buffers + Cached 顶一下。
  if (memAvail <= 0 && memTotal > 0) memAvail = memFree + buffers + cached;

  // 磁盘：/dev/vda1 41152736 8123456 30941234 21% /
  int diskTotal = 0;
  int diskUsed = 0;
  final List<String> df = blocks['DF'] ?? const <String>[];
  if (df.isNotEmpty) {
    final List<String> cols = df.first.trim().split(RegExp(r'\s+'));
    if (cols.length >= 4 && cols.first.startsWith('/')) {
      diskTotal = int.tryParse(cols[1]) ?? 0;
      diskUsed = int.tryParse(cols[2]) ?? 0;
    }
  }

  // 网络：累计字节，lo 不算。
  int rx = 0;
  int tx = 0;
  for (final String line in blocks['NET'] ?? const <String>[]) {
    final int colon = line.indexOf(':');
    if (colon < 0) continue;
    final String name = line.substring(0, colon).trim();
    if (name == 'lo' || name.isEmpty) continue;
    final List<String> cols = line.substring(colon + 1).trim().split(RegExp(r'\s+'));
    if (cols.length < 9) continue;
    rx += int.tryParse(cols[0]) ?? 0;
    tx += int.tryParse(cols[8]) ?? 0;
  }

  final double? cpu = _cpuPercent(blocks['CPU1'], blocks['CPU2']);

  return HostMetrics(
    at: now ?? DateTime.now(),
    os: kernel,
    uptimeSeconds: upSeconds.toInt(),
    load1: pick(0),
    load5: pick(1),
    load15: pick(2),
    cores: coreCount,
    cpuPercent: cpu,
    memTotalKb: memTotal,
    memAvailKb: memAvail,
    swapTotalKb: swapTotal,
    swapFreeKb: swapFree,
    diskTotalKb: diskTotal,
    diskUsedKb: diskUsed,
    netRx: rx,
    netTx: tx,
  );
}

/// 两次 `cpu a b c …` 之间的占用。idle + iowait 都算空着。
double? _cpuPercent(List<String>? first, List<String>? second) {
  if (first == null || second == null || first.isEmpty || second.isEmpty) return null;
  final List<int> a = _cpuTicks(first.first);
  final List<int> b = _cpuTicks(second.first);
  if (a.length < 8 || b.length < 8) return null;
  int totalA = 0;
  int idleA = 0;
  int totalB = 0;
  int idleB = 0;
  for (int i = 0; i < 8; i += 1) {
    totalA += a[i];
    totalB += b[i];
  }
  idleA = a[3] + a[4];
  idleB = b[3] + b[4];
  final int total = totalB - totalA;
  final int idle = idleB - idleA;
  if (total <= 0) return null;
  final double busy = (total - idle) * 100 / total;
  return busy < 0 ? 0 : (busy > 100 ? 100 : busy);
}

List<int> _cpuTicks(String line) {
  final List<String> parts = line.trim().split(RegExp(r'\s+'));
  final List<int> out = <int>[];
  for (int i = 1; i < parts.length && i <= 10; i += 1) {
    out.add(int.tryParse(parts[i]) ?? 0);
  }
  return out;
}

/// 前后两次采样之间网络跑多快。第一次没有前值，给 null。
double? rateBetween(int now, int before, Duration span) {
  if (span.inMilliseconds <= 0) return null;
  final int delta = now - before;
  if (delta < 0) return null;
  return delta * 1000 / span.inMilliseconds;
}
