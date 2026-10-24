/// 资源监听：某台机器的某项指标过了线，或者有人异常登录，就发一条通知。
///
/// 这种任务不叫模型，只看数字和登录记录。纯 Dart：不 import Flutter。
library;

import 'monitor.dart';

/// 看什么。
///
/// - `metric`：CPU、内存、磁盘、交换、负载。
/// - `loginFail`：一段窗口内失败登录的次数。
/// - `loginNew`：出现了没见过的来源 IP 的成功登录。
enum WatchKind { metric, loginFail, loginNew }

const Map<WatchKind, String> kWatchKindNames = <WatchKind, String>{
  WatchKind.metric: '资源指标',
  WatchKind.loginFail: '失败登录',
  WatchKind.loginNew: '新 IP 登录',
};

enum WatchMetric { cpu, memory, disk, swap, load }

const Map<WatchMetric, String> kWatchNames = <WatchMetric, String>{
  WatchMetric.cpu: 'CPU',
  WatchMetric.memory: '内存',
  WatchMetric.disk: '磁盘',
  WatchMetric.swap: '交换',
  WatchMetric.load: '负载',
};

/// `last` / `lastb` 里的一行登录记录。
class LoginEvent {
  LoginEvent({required this.user, required this.host, this.at});

  final String user;

  /// 来源：IP、主机名，控制台是 `:0` 这种。
  final String host;
  final DateTime? at;

  bool get remote => host.isNotEmpty && !host.startsWith(':');
}

const Map<String, int> _months = <String, int>{
  'Jan': 1,
  'Feb': 2,
  'Mar': 3,
  'Apr': 4,
  'May': 5,
  'Jun': 6,
  'Jul': 7,
  'Aug': 8,
  'Sep': 9,
  'Oct': 10,
  'Nov': 11,
  'Dec': 12,
};

const Set<String> _weekdays = <String>{
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
};

/// 读 `LC_ALL=C last -w -F` 或 `lastb -F` 的输出。
///
/// 一行是 `用户 终端 来源 周一 月 日 时:分:秒 年 ...`，控制台登录没有来源那一格。
/// `reboot` / `wtmp begins` / `btmp begins` 这类行跳过。
List<LoginEvent> parseLastLog(String text) {
  final List<LoginEvent> out = <LoginEvent>[];
  for (final String raw in text.split('\n')) {
    final String line = raw.trimRight();
    if (line.trim().isEmpty) continue;
    final List<String> t = line.trim().split(RegExp(r'\s+'));
    if (t.length < 5) continue;
    final String user = t.first;
    if (user == 'reboot' || user == 'shutdown' || user == 'wtmp' || user == 'btmp') {
      continue;
    }
    if (line.contains(' begins ') || line.startsWith('last:')) continue;
    int day = -1;
    for (int i = 2; i < t.length; i += 1) {
      if (_weekdays.contains(t[i])) {
        day = i;
        break;
      }
    }
    if (day < 0 || day + 4 >= t.length) continue;
    final int? month = _months[t[day + 1]];
    final int? date = int.tryParse(t[day + 2]);
    final List<String> clock = t[day + 3].split(':');
    final int? year = int.tryParse(t[day + 4]);
    final String host = day > 2 ? t.sublist(2, day).join(' ') : '';
    DateTime? at;
    if (month != null && date != null && year != null && clock.length >= 2) {
      final int hour = int.tryParse(clock[0]) ?? 0;
      final int minute = int.tryParse(clock[1]) ?? 0;
      final int second = clock.length > 2 ? (int.tryParse(clock[2]) ?? 0) : 0;
      final DateTime guess = DateTime(year, month, date, hour, minute, second);
      // `last` 不带时区，读成当地时间；差太远八成是跨年的老记录，不动它。
      at = guess;
    }
    out.add(LoginEvent(user: user, host: host, at: at));
  }
  return out;
}

/// 一次读数。fired 表示这一次真的发了通知。
class WatchHit {
  WatchHit({required this.at, this.value, this.fired = false, this.error = ''});

  final DateTime at;

  /// 读到的值。指标类：百分比或负载；失败登录：次数；新 IP：几个。
  final double? value;
  final bool fired;
  final String error;

  String get stamp {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'at': at.toIso8601String(),
        if (value != null) 'value': value,
        if (fired) 'fired': true,
        if (error.isNotEmpty) 'error': error,
      };

  static WatchHit fromJson(Map<String, Object?> json) => WatchHit(
        at: DateTime.tryParse('${json['at'] ?? ''}') ?? DateTime.now(),
        value: (json['value'] as num?)?.toDouble(),
        fired: json['fired'] == true,
        error: '${json['error'] ?? ''}',
      );
}

/// 一条监听规则。
class WatchTask {
  WatchTask({
    required this.id,
    required this.title,
    required this.hostId,
    this.kind = WatchKind.metric,
    this.metric = WatchMetric.disk,
    this.above = true,
    this.threshold = 90,
    this.windowMinutes = 10,
    this.intervalMinutes = 5,
    this.cooldownMinutes = 30,
    this.enabled = true,
    DateTime? createdAt,
    this.nextAt,
    this.lastAlertAt,
    List<WatchHit>? hits,
    Set<String>? knownIps,
  })  : createdAt = createdAt ?? DateTime.now(),
        hits = hits ?? <WatchHit>[],
        knownIps = knownIps ?? <String>{};

  final String id;
  String title;
  String hostId;
  WatchKind kind;
  WatchMetric metric;

  /// true = 超过阈值提醒，false = 低于阈值提醒（比如剩余空间）。
  bool above;

  /// 指标类：百分比或负载。失败登录：次数。
  double threshold;

  /// 失败登录的回看窗口，多少分钟。
  int windowMinutes;

  /// 多少分钟读一次。
  int intervalMinutes;

  /// 提醒过之后歇多久再说。
  int cooldownMinutes;
  bool enabled;
  final DateTime createdAt;
  DateTime? nextAt;
  DateTime? lastAlertAt;

  /// 最新在最前面，只留十条。
  final List<WatchHit> hits;

  /// 见过的来源，新 IP 登录靠它判「新」。只留最近的 200 个。
  final Set<String> knownIps;

  static const int maxHits = 10;
  static const int maxIps = 200;

  String get metricName => kWatchNames[metric] ?? '指标';

  String get kindName => kWatchKindNames[kind] ?? '监听';

  int get intervalStep => _clamp(intervalMinutes, 1, 720);

  int get cooldownStep => _clamp(cooldownMinutes, 1, 1440);

  int get windowStep => _clamp(windowMinutes, 1, 1440);

  static int _clamp(int v, int low, int high) {
    final int a = v < low ? low : v;
    return a > high ? high : a;
  }

  String get _every {
    final int m = intervalStep;
    if (m % 60 == 0) return '每 ${m ~/ 60} 小时';
    return '每 $m 分钟';
  }

  /// 阈值怎么写：负载是光数字，其余带百分号。
  String get thresholdText =>
      kind == WatchKind.metric && metric == WatchMetric.load
          ? numberText(threshold)
          : (kind == WatchKind.metric ? '${numberText(threshold)}%' : numberText(threshold));

  /// `每 5 分钟看一次 · 磁盘 > 90%`
  String get when {
    switch (kind) {
      case WatchKind.loginFail:
        return '$_every看一次 · ${windowStep} 分钟内失败登录 ≥ '
            '${numberText(threshold)} 次';
      case WatchKind.loginNew:
        return '$_every看一次 · 出现没见过的 IP 登录';
      case WatchKind.metric:
        return '$_every看一次 · $metricName ${above ? '>' : '<'} $thresholdText';
    }
  }

  /// 读一次这台机器的这一项。读不到就给 null。
  double? valueOf(HostMetrics m) {
    switch (metric) {
      case WatchMetric.cpu:
        return m.cpuPercent;
      case WatchMetric.memory:
        return m.memPercent;
      case WatchMetric.disk:
        return m.diskPercent;
      case WatchMetric.swap:
        return m.swapTotalKb <= 0 ? null : m.swapPercent;
      case WatchMetric.load:
        return m.load1;
    }
  }

  bool passes(double value) => above ? value > threshold : value < threshold;

  /// 小数点后没东西就不写，90.0 写成 90。
  static String numberText(double v) {
    final String text = v.toStringAsFixed(2);
    if (text.endsWith('.00')) return text.substring(0, text.length - 3);
    if (text.endsWith('0')) return text.substring(0, text.length - 1);
    return text;
  }

  /// 值怎么写：指标负载两位小数、其余带百分号；登录类带单位。
  String valueText(double value) {
    switch (kind) {
      case WatchKind.loginFail:
        return '${value.round()} 次';
      case WatchKind.loginNew:
        return '${value.round()} 个新 IP';
      case WatchKind.metric:
        return metric == WatchMetric.load
            ? value.toStringAsFixed(2)
            : '${value.round()}%';
    }
  }

  /// 通知上那句。
  String alertBody(String hostName, double value, {String extra = ''}) {
    switch (kind) {
      case WatchKind.loginFail:
        return '$hostName ${windowStep} 分钟内失败登录 ${value.round()} 次';
      case WatchKind.loginNew:
        return '$hostName 有没见过的来源登录${extra.isEmpty ? '' : '：$extra'}';
      case WatchKind.metric:
        return '$hostName $metricName ${valueText(value)}（'
            '${above ? '超过' : '低于'} $thresholdText）';
    }
  }

  /// 判一次新 IP 登录，返回没见过的那些。顺手记下来。
  List<String> takeNewHosts(Iterable<LoginEvent> events) {
    final List<String> fresh = <String>[];
    for (final LoginEvent e in events) {
      if (!e.remote) continue;
      final String key = e.host.toLowerCase();
      if (knownIps.contains(key)) continue;
      if (fresh.contains(e.host)) continue;
      fresh.add(e.host);
    }
    for (final String host in fresh) {
      knownIps.add(host.toLowerCase());
    }
    while (knownIps.length > maxIps) {
      knownIps.remove(knownIps.first);
    }
    return fresh;
  }

  void addHit(WatchHit hit) {
    hits.insert(0, hit);
    while (hits.length > maxHits) {
      hits.removeLast();
    }
  }

  WatchHit? get lastHit => hits.isEmpty ? null : hits.first;

  void scheduleFrom(DateTime now) {
    nextAt = now.add(Duration(minutes: intervalStep));
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'hostId': hostId,
        'kind': kind.name,
        'metric': metric.name,
        'above': above,
        'threshold': threshold,
        'windowMinutes': windowMinutes,
        'intervalMinutes': intervalMinutes,
        'cooldownMinutes': cooldownMinutes,
        'enabled': enabled,
        'createdAt': createdAt.toIso8601String(),
        if (nextAt != null) 'nextAt': nextAt!.toIso8601String(),
        if (lastAlertAt != null) 'lastAlertAt': lastAlertAt!.toIso8601String(),
        if (knownIps.isNotEmpty) 'knownIps': knownIps.toList(),
        'hits': hits.map((WatchHit h) => h.toJson()).toList(),
      };

  static WatchTask fromJson(Map<String, Object?> json) {
    final Object? rawHits = json['hits'];
    final List<WatchHit> hits = <WatchHit>[];
    if (rawHits is List) {
      for (final Object? raw in rawHits) {
        if (raw is Map) hits.add(WatchHit.fromJson(Map<String, Object?>.from(raw)));
      }
    }
    final Set<String> ips = <String>{};
    final Object? rawIps = json['knownIps'];
    if (rawIps is List) {
      for (final Object? raw in rawIps) {
        final String ip = '$raw'.trim();
        if (ip.isNotEmpty) ips.add(ip);
      }
    }
    WatchKind kind = WatchKind.metric;
    for (final WatchKind k in WatchKind.values) {
      if (k.name == '${json['kind'] ?? ''}') kind = k;
    }
    WatchMetric metric = WatchMetric.disk;
    for (final WatchMetric m in WatchMetric.values) {
      if (m.name == '${json['metric'] ?? ''}') metric = m;
    }
    return WatchTask(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      hostId: '${json['hostId'] ?? ''}',
      kind: kind,
      metric: metric,
      above: json['above'] != false,
      threshold: (json['threshold'] as num?)?.toDouble() ?? 90,
      windowMinutes: (json['windowMinutes'] as num?)?.toInt() ?? 10,
      intervalMinutes: (json['intervalMinutes'] as num?)?.toInt() ?? 5,
      cooldownMinutes: (json['cooldownMinutes'] as num?)?.toInt() ?? 30,
      enabled: json['enabled'] != false,
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}') ?? DateTime.now(),
      nextAt: DateTime.tryParse('${json['nextAt'] ?? ''}'),
      lastAlertAt: DateTime.tryParse('${json['lastAlertAt'] ?? ''}'),
      hits: hits,
      knownIps: ips,
    );
  }
}
