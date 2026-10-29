/// 模型参数：一个值、一个范围、一个锁，还有「谁改的」。
///
/// 这一层只管规则，不碰界面也不碰文件。AI 想调参数时先在这里过一遍：
/// 超范围、锁着、用户没让它调，都在这里被拦下来，并且原样回一句人话。
library;

/// 一个能调的参数：叫什么、默认多少、允许从哪儿到哪儿。
class ParamSpec {
  const ParamSpec({
    required this.key,
    required this.label,
    required this.min,
    required this.max,
    required this.fallback,
    this.unit = '',
  });

  /// 请求体里那个字段名，也是存进配置的键。
  final String key;

  /// 界面上怎么称呼它。
  final String label;

  /// 出厂允许范围。用户可以在设置里改窄或改宽。
  final double min;
  final double max;

  /// 没动过的时候用多少。
  final double fallback;

  /// 写在数字后面的单位，没有就空着。
  final String unit;

  /// 值怎么写给人看。
  String format(double value) => '${_trim(value)}$unit';

  String get span => '${_trim(min)}–${_trim(max)}${unit.isEmpty ? '' : unit}';
}

String _trim(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

/// 现在能调的那几个。以后加参数只动这张表。
const List<ParamSpec> kParamSpecs = <ParamSpec>[
  ParamSpec(key: 'temperature', label: '温度', min: 0, max: 2, fallback: 0.2),
];

ParamSpec? paramSpecOf(String key) {
  for (final ParamSpec s in kParamSpecs) {
    if (s.key == key) return s;
  }
  return null;
}

/// 一个参数落在某套配置上的样子：值、锁、来源、理由、什么时候。
class ParamState {
  ParamState({
    required this.value,
    this.locked = false,
    this.source = '',
    this.reason = '',
    this.at = '',
  });

  double value;

  /// 锁上之后 AI 改不动，用户自己还能改。
  bool locked;

  /// `ai` = AI 建议、用户确认过的；`user` = 用户手填的；空 = 出厂默认。
  String source;

  /// AI 当时为什么这么调，给用户复看。
  String reason;

  /// 最后一次动它的时间，ISO 800 字串。
  String at;

  bool get fromAi => source == 'ai';

  String get sourceLabel => switch (source) {
        'ai' => 'AI 建议',
        'user' => '手动',
        _ => '默认',
      };

  Map<String, Object?> toJson() => <String, Object?>{
        'value': value,
        if (locked) 'locked': true,
        if (source.isNotEmpty) 'source': source,
        if (reason.isNotEmpty) 'reason': reason,
        if (at.isNotEmpty) 'at': at,
      };

  static ParamState? fromJson(Map<String, Object?> json) {
    final Object? raw = json['value'];
    final double? value = raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}');
    if (value == null) return null;
    return ParamState(
      value: value,
      locked: json['locked'] == true,
      source: '${json['source'] ?? ''}',
      reason: '${json['reason'] ?? ''}',
      at: '${json['at'] ?? ''}',
    );
  }
}

/// 一个参数这次允许落在什么范围里。
class ParamRange {
  const ParamRange(this.low, this.high);

  final double low;
  final double high;

  String get text => '${_trim(low)}–${_trim(high)}';

  bool holds(double v) => v >= low && v <= high;
}

/// 出厂范围，外面再套一层用户在设置里改过的窄范围。
ParamRange paramRangeOf(String key, {Map<String, List<double>> overrides = const <String, List<double>>{}}) {
  final ParamSpec? spec = paramSpecOf(key);
  final double low = spec?.min ?? 0;
  final double high = spec?.max ?? 1;
  final List<double>? own = overrides[key];
  if (own == null || own.length < 2) return ParamRange(low, high);
  final double a = own[0];
  final double b = own[1];
  if (a.isNaN || b.isNaN) return ParamRange(low, high);
  final double lo = a < low ? low : a;
  final double hi = b > high ? high : b;
  if (lo >= hi) return ParamRange(low, high);
  return ParamRange(lo, hi);
}

/// 一次改动成没成。没成也带一句给人看的话。
class ParamEdit {
  const ParamEdit({required this.ok, required this.text, this.value, this.state});

  final bool ok;
  final String text;

  /// 改完之后的值。
  final double? value;
  final ParamState? state;

  static ParamEdit fail(String text) => ParamEdit(ok: false, text: text);
}

/// 把一次改动落进这套配置的参数字典里。
///
/// [params] 就是那套配置的表，改完直接生效；要不要存盘由调用方决定。
/// [byAi] 为真时锁着的一律不动；用户自己改（[byAi] 为假）锁不拦。
ParamEdit applyParam(
  Map<String, ParamState> params, {
  required String key,
  required double value,
  required ParamRange range,
  bool byAi = false,
  String reason = '',
  DateTime? at,
}) {
  final ParamSpec? spec = paramSpecOf(key);
  if (spec == null) return ParamEdit.fail('没有这个参数：$key');
  if (value.isNaN || value.isInfinite) return ParamEdit.fail('${spec.label}得是个数。');
  final ParamState? now = params[key];
  if (byAi && (now?.locked ?? false)) {
    return ParamEdit.fail('${spec.label}锁着，AI 不改它。要改先解锁，或者自己填。');
  }
  if (!range.holds(value)) {
    return ParamEdit.fail(
        '${spec.label}只能落在 ${range.text} 之间，$value 超了。');
  }
  final double before = now?.value ?? spec.fallback;
  final ParamState next = now ?? ParamState(value: value);
  next.value = value;
  if (!byAi) {
    // 用户自己写的一律算手动，锁保持原样。
    next.source = 'user';
    next.reason = reason;
  } else {
    next.source = 'ai';
    next.reason = reason;
  }
  next.at = (at ?? DateTime.now()).toIso8601String();
  params[key] = next;
  final String move = (before - value).abs() < 0.0005
      ? '还是 ${spec.format(value)}'
      : '${spec.format(before)} → ${spec.format(value)}';
  return ParamEdit(
    ok: true,
    text: '${spec.label}$move${reason.isEmpty ? '' : '，理由：$reason'}',
    value: value,
    state: next,
  );
}

/// 锁上或解开一个参数。用户自己点的那一下，不问理由。
ParamState setParamLock(
  Map<String, ParamState> params, {
  required String key,
  required bool locked,
  DateTime? at,
}) {
  final ParamSpec? spec = paramSpecOf(key);
  final ParamState state =
      params[key] ?? ParamState(value: spec?.fallback ?? 0, source: '');
  state.locked = locked;
  state.at = (at ?? DateTime.now()).toIso8601String();
  params[key] = state;
  return state;
}

/// 把这个参数恢复出厂：值、来源、理由一起清掉，锁留着。
ParamState resetParam(Map<String, ParamState> params, {required String key}) {
  final ParamSpec? spec = paramSpecOf(key);
  final ParamState state = params[key] ?? ParamState(value: spec?.fallback ?? 0);
  state.value = spec?.fallback ?? 0;
  state.source = '';
  state.reason = '';
  state.at = DateTime.now().toIso8601String();
  params[key] = state;
  return state;
}

/// 这套配置现在用什么温度，给请求体用。
double temperatureOf({
  required Map<String, ParamState> params,
  required double fallback,
}) {
  final double? own = params['temperature']?.value;
  if (own == null) return fallback;
  return own;
}
