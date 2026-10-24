/// 定时任务前面的那道判断：先读这台机器的数字，符合了才叫模型。
///
/// 纯 Dart：不 import Flutter，不碰网络，也不读文件，判断本身可以单独测。
/// 一条规则是「磁盘 > 90」这样的一句，几条用「都满足」或者「满足一条」连起来。
library;

import 'monitor.dart';

/// 条件能看的那几项，和资源监听看的是同一份数字。
enum RuleMetric { cpu, memory, disk, swap, load }

const Map<RuleMetric, String> kRuleMetricNames = <RuleMetric, String>{
  RuleMetric.cpu: 'CPU',
  RuleMetric.memory: '内存',
  RuleMetric.disk: '磁盘',
  RuleMetric.swap: '交换',
  RuleMetric.load: '负载',
};

/// 写法认这几个：`> 90`、`>= 90`、`< 4`、`<= 4`。
enum RuleOp { gt, ge, lt, le }

const Map<RuleOp, String> kRuleOpNames = <RuleOp, String>{
  RuleOp.gt: '>',
  RuleOp.ge: '≥',
  RuleOp.lt: '<',
  RuleOp.le: '≤',
};

/// 90.0 写成 90，90.5 写成 90.5。
String ruleNumber(double v) {
  final String text = v.toStringAsFixed(2);
  if (text.endsWith('.00')) return text.substring(0, text.length - 3);
  if (text.endsWith('0')) return text.substring(0, text.length - 1);
  return text;
}

/// 一条判断。负载不带百分号，其余按百分比。
class TaskRule {
  TaskRule({required this.metric, this.op = RuleOp.gt, required this.value});

  final RuleMetric metric;
  final RuleOp op;
  final double value;

  /// `磁盘 > 90`
  String get text =>
      '${kRuleMetricNames[metric]} ${kRuleOpNames[op]} ${ruleNumber(value)}';

  bool passes(double reading) {
    switch (op) {
      case RuleOp.gt:
        return reading > value;
      case RuleOp.ge:
        return reading >= value;
      case RuleOp.lt:
        return reading < value;
      case RuleOp.le:
        return reading <= value;
    }
  }

  /// 读数的写法：负载是两位小数，其余带百分号。
  String readingText(double reading) => metric == RuleMetric.load
      ? ruleNumber(reading)
      : '${reading.round()}%';

  Map<String, Object?> toJson() => <String, Object?>{
        'metric': metric.name,
        'op': op.name,
        'value': value,
      };

  static TaskRule? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Map<String, Object?> json = Map<String, Object?>.from(raw);
    final RuleMetric? metric = metricOf('${json['metric'] ?? ''}');
    if (metric == null) return null;
    final Object? value = json['value'];
    final double? number = value is num ? value.toDouble() : double.tryParse('$value');
    if (number == null) return null;
    return TaskRule(metric: metric, op: opOf('${json['op'] ?? ''}') ?? RuleOp.gt, value: number);
  }

  /// 读清单里的旧数据时用，认不出就是 null。
  static RuleMetric? metricOf(String name) {
    final String key = name.trim().toLowerCase();
    for (final RuleMetric m in RuleMetric.values) {
      if (m.name == key) return m;
    }
    return _metricAlias[key];
  }

  static RuleOp? opOf(String text) {
    switch (text.trim()) {
      case 'gt':
      case '>':
        return RuleOp.gt;
      case 'ge':
      case '>=':
      case '≥':
        return RuleOp.ge;
      case 'lt':
      case '<':
        return RuleOp.lt;
      case 'le':
      case '<=':
      case '≤':
        return RuleOp.le;
    }
    return null;
  }
}

const Map<String, RuleMetric> _metricAlias = <String, RuleMetric>{
  'c': RuleMetric.cpu,
  'processor': RuleMetric.cpu,
  '处理器': RuleMetric.cpu,
  'mem': RuleMetric.memory,
  'ram': RuleMetric.memory,
  '内存': RuleMetric.memory,
  'd': RuleMetric.disk,
  'root': RuleMetric.disk,
  '磁盘': RuleMetric.disk,
  '空间': RuleMetric.disk,
  'swap': RuleMetric.swap,
  '交换': RuleMetric.swap,
  'load': RuleMetric.load,
  'load1': RuleMetric.load,
  '负载': RuleMetric.load,
};

/// 这台机器上这一项的读数。没有这一项（没交换分区、读不到 CPU）给 null。
double? ruleReading(RuleMetric metric, HostMetrics m) {
  switch (metric) {
    case RuleMetric.cpu:
      return m.cpuPercent;
    case RuleMetric.memory:
      return m.memTotalKb <= 0 ? null : 100 * (1 - m.memAvailKb / m.memTotalKb);
    case RuleMetric.disk:
      return m.diskTotalKb <= 0 ? null : 100 * m.diskUsedKb / m.diskTotalKb;
    case RuleMetric.swap:
      return m.swapTotalKb <= 0 ? null : 100 * (1 - m.swapFreeKb / m.swapTotalKb);
    case RuleMetric.load:
      return m.load1;
  }
}

/// `磁盘>90`、`disk > 90%`、`负载 >= 4` 都读得出来。读不出来给 null。
TaskRule? parseRule(String text) {
  final Match? match = RegExp(r'^([^<>≤≥=]{1,10}?)\s*(>=|<=|≥|≤|>|<)\s*(-?[\d.]+)\s*%?$')
      .firstMatch(text.trim());
  if (match == null) return null;
  final RuleMetric? metric = TaskRule.metricOf(match.group(1)!);
  final RuleOp? op = TaskRule.opOf(match.group(2)!);
  final double? value = double.tryParse(match.group(3)!);
  if (metric == null || op == null || value == null) return null;
  return TaskRule(metric: metric, op: op, value: value);
}

/// `磁盘 > 90 且 CPU > 80`
String rulesText(List<TaskRule> rules, {bool all = true}) {
  if (rules.isEmpty) return '';
  final String join = all ? ' 且 ' : ' 或 ';
  return rules.map((TaskRule r) => r.text).join(join);
}

/// 判一次的结果：符不符合，加上一句话说明现在的读数差在哪。
class RuleCheck {
  RuleCheck({required this.met, this.text = '', this.misses = const <String>[]});

  final bool met;

  /// 符合时是读数本身（`磁盘 92%`），不符合时是没过的那些（`磁盘 78%（要 > 90）`）。
  final String text;
  final List<String> misses;

  bool get empty => text.isEmpty && misses.isEmpty;
}

/// 拿一次读数判一遍。[all] 为真表示全都要满足，否则满足一条就够。
RuleCheck checkRules(List<TaskRule> rules, {bool all = true, required HostMetrics metrics}) {
  if (rules.isEmpty) return RuleCheck(met: true);
  final List<String> readings = <String>[];
  final List<String> misses = <String>[];
  for (final TaskRule rule in rules) {
    final double? value = ruleReading(rule.metric, metrics);
    if (value == null) {
      misses.add('${kRuleMetricNames[rule.metric]}读不到');
      continue;
    }
    final String reading =
        '${kRuleMetricNames[rule.metric]} ${rule.readingText(value)}';
    readings.add(reading);
    if (!rule.passes(value)) misses.add('$reading（要 ${rule.text}）');
  }
  final bool met = all ? misses.isEmpty : readings.isNotEmpty && misses.length < rules.length;
  if (met) {
    return RuleCheck(met: true, text: readings.join('、'));
  }
  return RuleCheck(met: false, text: misses.join('、'), misses: misses);
}
