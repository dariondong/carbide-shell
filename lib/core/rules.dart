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

/// 一组条件怎么连：都满足，或者满足一条。
enum RuleLogic { all, any }

/// 选的那一格上写什么。
const Map<RuleLogic, String> kRuleLogicNames = <RuleLogic, String>{
  RuleLogic.all: '全部满足',
  RuleLogic.any: '满足一条',
};

String ruleJoinWord(RuleLogic logic) => logic == RuleLogic.all ? ' 且 ' : ' 或 ';

/// 条件树的一个节点：一条判断，或者一组判断。
///
/// 组里可以再放组，所以「磁盘快满，而且（CPU 高或者内存高）」这种写法也立得住。
/// 字段都是可改的：编辑页在树上改完再存。
class RuleNode {
  RuleNode.rule(TaskRule this.rule)
      : logic = RuleLogic.all,
        children = <RuleNode>[];

  RuleNode.group({this.logic = RuleLogic.all, List<RuleNode>? children})
      : rule = null,
        children = children ?? <RuleNode>[];

  /// 叶子节点上的那条判断，组上是 null。
  TaskRule? rule;

  /// 组怎么连；叶子节点这一项没意义。
  RuleLogic logic;

  final List<RuleNode> children;

  bool get isGroup => rule == null;

  /// 树上有几条判断。
  int get leaves =>
      isGroup ? children.fold<int>(0, (int sum, RuleNode c) => sum + c.leaves) : 1;

  /// 最深几层，叶子算一层。
  int get depth => isGroup
      ? 1 +
          children.fold<int>(
              0, (int most, RuleNode c) => c.depth > most ? c.depth : most)
      : 1;

  String get joinWord => ruleJoinWord(logic);

  /// 一条判断就是它自己；一组带括号，嵌在别人里面也读得清。
  String get text => isGroup
      ? '（${children.map((RuleNode c) => c.text).join(joinWord)}）'
      : rule!.text;

  RuleNode deepCopy() => isGroup
      ? RuleNode.group(
          logic: logic,
          children: children.map((RuleNode c) => c.deepCopy()).toList())
      : RuleNode.rule(
          TaskRule(metric: rule!.metric, op: rule!.op, value: rule!.value));

  /// 一组只装一条时收成那一条，省得念出来多一层括号。
  RuleNode collapse() {
    if (!isGroup) return this;
    for (int i = 0; i < children.length; i += 1) {
      children[i] = children[i].collapse();
    }
    if (children.length == 1) return children.first;
    return this;
  }

  Map<String, Object?> toJson() => isGroup
      ? <String, Object?>{
          'logic': logic.name,
          'children': children.map((RuleNode c) => c.toJson()).toList(),
        }
      : rule!.toJson();

  static RuleNode? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Object? kids = raw['children'];
    if (kids is List) {
      final List<RuleNode> children = <RuleNode>[];
      for (final Object? item in kids) {
        final RuleNode? node = fromJson(item);
        if (node != null) children.add(node);
      }
      if (children.isEmpty) return null;
      return RuleNode.group(
        logic: '${raw['logic'] ?? ''}' == 'any' ? RuleLogic.any : RuleLogic.all,
        children: children,
      );
    }
    final TaskRule? rule = TaskRule.fromJson(raw);
    return rule == null ? null : RuleNode.rule(rule);
  }
}

/// 顶层那一句：不加外层的括号，`磁盘 > 90 且 CPU > 80`。
String conditionTextOf(RuleNode? node) {
  if (node == null) return '';
  if (!node.isGroup) return node.text;
  if (node.children.isEmpty) return '';
  return node.children.map((RuleNode c) => c.text).join(node.joinWord);
}

/// 把 `磁盘>90 且 (CPU>80 或 内存>=85)` 读成一棵树。读不出来给 null。
RuleNode? parseCondition(String text) {
  final List<String> tokens = _conditionTokens(text);
  if (tokens.isEmpty) return null;
  final _ConditionParser parser = _ConditionParser(tokens);
  final RuleNode? node = parser.parseOr();
  if (node == null || !parser.done) return null;
  return node;
}

const List<String> _condJoin = <String>['||', '&&', '且', '和', '与', '或', 'and', 'or'];

/// 括号和连词切出来，其余都是「一条判断」的原文。
List<String> _conditionTokens(String text) {
  final List<String> out = <String>[];
  final StringBuffer buf = StringBuffer();
  void flush() {
    final String piece = buf.toString().trim();
    if (piece.isNotEmpty) out.add(piece);
    buf.clear();
  }

  final String lower = text.toLowerCase();
  int i = 0;
  while (i < text.length) {
    final String ch = text[i];
    if (ch == '(' || ch == ')' || ch == '（' || ch == '）') {
      flush();
      out.add(ch == '(' || ch == '（' ? '(' : ')');
      i += 1;
      continue;
    }
    bool matched = false;
    for (final String op in _condJoin) {
      if (!lower.startsWith(op, i)) continue;
      // `and`/`or` 得是独立的词，不能从单词里切一刀。
      if (op == 'and' || op == 'or') {
        final String before = i == 0 ? '' : lower[i - 1];
        final String after =
            i + op.length >= lower.length ? '' : lower[i + op.length];
        if (_isLetter(before) || _isLetter(after)) continue;
      }
      flush();
      out.add(op == '或' || op == 'or' || op == '||' ? '或' : '且');
      i += op.length;
      matched = true;
      break;
    }
    if (matched) continue;
    buf.write(ch);
    i += 1;
  }
  flush();
  return out;
}

bool _isLetter(String ch) =>
    ch.length == 1 && ch.codeUnitAt(0) >= 0x61 && ch.codeUnitAt(0) <= 0x7a;

class _ConditionParser {
  _ConditionParser(this.tokens);

  final List<String> tokens;
  int _at = 0;

  bool get done => _at >= tokens.length;

  String? get _peek => _at < tokens.length ? tokens[_at] : null;

  /// 或比且松一层，所以 `a 且 b 或 c` 读成 `(a 且 b) 或 c`。
  RuleNode? parseOr() {
    final List<RuleNode> parts = <RuleNode>[];
    final RuleNode? first = parseAnd();
    if (first == null) return null;
    parts.add(first);
    while (_peek == '或') {
      _at += 1;
      final RuleNode? next = parseAnd();
      if (next == null) return null;
      parts.add(next);
    }
    return parts.length == 1
        ? parts.first
        : RuleNode.group(logic: RuleLogic.any, children: parts);
  }

  RuleNode? parseAnd() {
    final List<RuleNode> parts = <RuleNode>[];
    final RuleNode? first = parseAtom();
    if (first == null) return null;
    parts.add(first);
    while (_peek == '且') {
      _at += 1;
      final RuleNode? next = parseAtom();
      if (next == null) return null;
      parts.add(next);
    }
    return parts.length == 1
        ? parts.first
        : RuleNode.group(logic: RuleLogic.all, children: parts);
  }

  RuleNode? parseAtom() {
    final String? token = _peek;
    if (token == null) return null;
    if (token == '(') {
      _at += 1;
      final RuleNode? inner = parseOr();
      if (inner == null || _peek != ')') return null;
      _at += 1;
      return inner;
    }
    if (token == ')' || token == '且' || token == '或') return null;
    final TaskRule? rule = parseRule(token);
    if (rule == null) return null;
    _at += 1;
    return RuleNode.rule(rule);
  }
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

/// 拿一次读数判一遍平的一条条。[all] 为真表示全都要满足，否则满足一条就够。
RuleCheck checkRules(List<TaskRule> rules, {bool all = true, required HostMetrics metrics}) {
  if (rules.isEmpty) return RuleCheck(met: true);
  return checkCondition(
    RuleNode.group(
      logic: all ? RuleLogic.all : RuleLogic.any,
      children: rules.map((TaskRule r) => RuleNode.rule(r)).toList(),
    ),
    metrics: metrics,
  );
}

/// 拿一次读数按整棵树判一遍。空树算过。
RuleCheck checkCondition(RuleNode? node, {required HostMetrics metrics}) {
  if (node == null || node.leaves == 0) return RuleCheck(met: true);
  final _Eval result = _eval(node, metrics);
  final List<String> shown = result.met ? result.readings : result.misses;
  return RuleCheck(met: result.met, text: shown.join('、'), misses: result.misses);
}

/// 一条判断或一组判断判完的样子：过没过、念得出的读数、没过的那些。
class _Eval {
  _Eval(this.met, this.readings, this.misses);

  final bool met;
  final List<String> readings;
  final List<String> misses;
}

_Eval _eval(RuleNode node, HostMetrics metrics) {
  final TaskRule? rule = node.rule;
  if (rule != null) {
    final double? value = ruleReading(rule.metric, metrics);
    if (value == null) {
      return _Eval(false, <String>[], <String>['${kRuleMetricNames[rule.metric]}读不到']);
    }
    final String reading = '${kRuleMetricNames[rule.metric]} ${rule.readingText(value)}';
    final bool ok = rule.passes(value);
    return _Eval(
        ok, <String>[reading], ok ? <String>[] : <String>['$reading（要 ${rule.text}）']);
  }

  final List<_Eval> kids = node.children
      .where((RuleNode c) => c.leaves > 0)
      .map((RuleNode c) => _eval(c, metrics))
      .toList();
  if (kids.isEmpty) return _Eval(true, <String>[], <String>[]);

  if (node.logic == RuleLogic.all) {
    final List<String> readings = <String>[];
    final List<String> misses = <String>[];
    for (final _Eval kid in kids) {
      readings.addAll(kid.readings);
      misses.addAll(kid.misses);
    }
    return _Eval(misses.isEmpty, readings, misses);
  }

  // 满足一条：过了的那几支的读数留着当说明；一支都没过，就把每支差在哪列出来。
  final List<String> readings = <String>[];
  for (final _Eval kid in kids) {
    if (kid.met) readings.addAll(kid.readings);
  }
  if (readings.isNotEmpty) return _Eval(true, readings, <String>[]);
  final List<String> misses = <String>[];
  for (final _Eval kid in kids) {
    misses.add(kid.misses.isEmpty ? '有一组条件没过' : kid.misses.join(' 且 '));
  }
  return _Eval(false, <String>[], misses);
}
