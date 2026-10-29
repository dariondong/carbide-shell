import 'dart:convert';
import 'dart:io';

import '../core/params.dart';
import 'secrets.dart';

/// 一套模型配置：地址、模型名、和界面上那个名字。
///
/// 密钥不在这里，按 [id] 存在安全存储里（见 [modelSecretKeyFor]）。
/// 提示词和调过的参数跟着这一套走，切换配置时一起换。
class ModelProfile {
  ModelProfile({
    required this.id,
    this.name = '',
    this.baseUrl = '',
    this.model = '',
    this.prompt = '',
    this.userPrompt = '',
    Map<String, ParamState>? params,
    Map<String, Object?> price = const <String, Object?>{},
  })  : params = params ?? <String, ParamState>{},
        price = Map<String, Object?>.of(price);

  String id;
  String name;
  String baseUrl;
  String model;

  /// 这一套绑定的提示词。切到这套就换上它，别的不动。
  String prompt;

  /// 用户为这一套单独写的一份，优先级比 [prompt] 高。
  String userPrompt;

  /// 调过的参数。没动过的参数不在这张表里。
  final Map<String, ParamState> params;

  /// 报价：`{input, output, cache, currency, per}`，空着表示用内置那份。
  final Map<String, Object?> price;

  /// 清单上写什么：自己起的名字优先，其次模型名，都没有就说没填。
  String get label {
    final String own = name.trim();
    if (own.isNotEmpty) return own;
    final String m = model.trim();
    return m.isEmpty ? '未填模型' : m;
  }

  /// 这一个参数现在多少：没动过就是出厂默认。
  double paramValue(String key) {
    final ParamState? own = params[key];
    if (own != null) return own.value;
    return paramSpecOf(key)?.fallback ?? 0;
  }

  ParamState? paramState(String key) => params[key];

  bool paramLocked(String key) => params[key]?.locked ?? false;

  /// 这套配置有没有真的配完（地址和模型名都写了）。
  bool get complete => baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'model': model,
        if (prompt.isNotEmpty) 'prompt': prompt,
        if (userPrompt.isNotEmpty) 'userPrompt': userPrompt,
        if (params.isNotEmpty)
          'params': params.map((String k, ParamState v) => MapEntry<String, Object?>(k, v.toJson())),
        if (price.isNotEmpty) 'price': price,
      };

  static ModelProfile fromJson(Map<String, Object?> json) {
    final Map<String, ParamState> params = <String, ParamState>{};
    final Object? rawParams = json['params'];
    if (rawParams is Map) {
      for (final MapEntry<Object?, Object?> e in rawParams.entries) {
        final Object? v = e.value;
        if (v is! Map) continue;
        final ParamState? state = ParamState.fromJson(Map<String, Object?>.from(v));
        if (state != null) params['${e.key}'] = state;
      }
    }
    final Object? rawPrice = json['price'];
    return ModelProfile(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      baseUrl: '${json['baseUrl'] ?? ''}',
      model: '${json['model'] ?? ''}',
      prompt: '${json['prompt'] ?? ''}',
      userPrompt: '${json['userPrompt'] ?? ''}',
      params: params,
      price: rawPrice is Map ? Map<String, Object?>.from(rawPrice) : const <String, Object?>{},
    );
  }

  /// 换一份地址和模型名，其余（提示词、参数、报价）都留着。
  ModelProfile copyAs(String newId, {String? name}) => ModelProfile(
        id: newId,
        name: name ?? (this.name.isEmpty ? '' : '${this.name} 副本'),
        baseUrl: baseUrl,
        model: model,
        prompt: prompt,
        userPrompt: userPrompt,
        params: params.map((String k, ParamState v) => MapEntry<String, ParamState>(
            k,
            ParamState(
              value: v.value,
              locked: v.locked,
              source: v.source,
              reason: v.reason,
              at: v.at,
            ))),
        price: price,
      );
}

/// Everything the user typed on the settings page. No default address.
class AppSettings {
  AppSettings({
    String baseUrl = '',
    String model = '',
    List<ModelProfile> profiles = const <ModelProfile>[],
    String activeProfile = '',
    this.temperature = 0.2,
    this.maxSteps = 12,
    this.approvalMode = 'autoRead',
    this.allowedDomains = const <String>[],
    this.lastUpdateCheck = '',
    this.stream = true,
    this.contextChars = 60000,
    this.extraPrompt = '',
    this.systemPrompt = '',
    this.answerFont = 13.5,
    this.autoCheckUpdate = true,
    this.notifStyle = 'simple',
    this.autoCompact = true,
    this.enabledTools = const <String>[],
    this.aiTune = true,
    this.paramRanges = const <String, List<double>>{},
  }) {
    _profiles = List<ModelProfile>.of(profiles);
    _dedupeIds();
    if (_profiles.isEmpty) {
      // 老的文件只存了一个地址和一个模型名，把它变成第一套。
      _profiles.add(ModelProfile(id: 'p1', baseUrl: baseUrl, model: model));
      _active = 'p1';
      return;
    }
    _active = _profiles.any((ModelProfile p) => p.id == activeProfile)
        ? activeProfile
        : _profiles.first.id;
  }

  late List<ModelProfile> _profiles;
  late String _active;

  /// 所有配好的模型，顺序就是清单上的顺序。
  List<ModelProfile> get profiles => List<ModelProfile>.unmodifiable(_profiles);

  String get activeProfile => _active;

  /// 现在用的那套。永远不是 null：至少留一套。
  ModelProfile get active => _profiles.firstWhere(
        (ModelProfile p) => p.id == _active,
        orElse: () => _profiles.first,
      );

  /// 老代码读写这两个，就是读写当前这套配置。
  String get baseUrl => active.baseUrl;
  set baseUrl(String value) => active.baseUrl = value;
  String get model => active.model;
  set model(String value) => active.model = value;

  /// 按 id 找一套。找不到就是 null。
  ModelProfile? profileById(String id) {
    for (final ModelProfile p in _profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 这套配置现在的温度：调过就用调过的，没动过就用设置里那个滑块。
  double temperatureFor(ModelProfile profile) =>
      temperatureOf(params: profile.params, fallback: temperature);

  /// 复制一份配置：提示词、参数、报价一起拷，密钥不拷。
  ModelProfile duplicateProfile(String id, {String name = ''}) {
    final ModelProfile? from = profileById(id);
    if (from == null) return active;
    final ModelProfile copy = from.copyAs(_nextId(), name: name.isEmpty ? null : name);
    _profiles.add(copy);
    _active = copy.id;
    return copy;
  }

  /// 把某一套设成默认（也就是现在用的那一套）。
  bool setDefault(String id) {
    if (!_profiles.any((ModelProfile p) => p.id == id)) return false;
    _active = id;
    return true;
  }

  /// 切到另一套。id 不存在就什么都不做。
  void switchProfile(String id) {
    if (_profiles.any((ModelProfile p) => p.id == id)) _active = id;
  }

  /// 加一套空的，并且切过去。地址不预填，名字空着等用户写。
  ModelProfile addProfile({String name = ''}) {
    final ModelProfile p = ModelProfile(id: _nextId(), name: name);
    _profiles.add(p);
    _active = p.id;
    return p;
  }

  /// 删掉一套。只剩一套时不删，返回 false。
  bool removeProfile(String id) {
    if (_profiles.length <= 1) return false;
    final int at = _profiles.indexWhere((ModelProfile p) => p.id == id);
    if (at < 0) return false;
    _profiles.removeAt(at);
    if (_active == id) {
      _active = _profiles[at < _profiles.length ? at : _profiles.length - 1].id;
    }
    return true;
  }

  String _nextId() {
    int n = _profiles.length + 1;
    while (_profiles.any((ModelProfile p) => p.id == 'p$n')) {
      n += 1;
    }
    return 'p$n';
  }

  /// 一条配置的 id 空着或者重名会让切换错位，读进来就先补一遍。
  void _dedupeIds() {
    final Set<String> seen = <String>{};
    for (int i = 0; i < _profiles.length; i += 1) {
      final ModelProfile p = _profiles[i];
      String id = p.id.trim();
      if (id.isEmpty || seen.contains(id)) {
        id = 'p${i + 1}';
        while (seen.contains(id)) {
          id = '$id-${seen.length}';
        }
      }
      p.id = id;
      seen.add(id);
    }
  }

  double temperature;
  int maxSteps;

  /// `autoRead` / `autoAll` / `askAll`.
  String approvalMode;

  /// Hosts `http_request` may reach. Empty means nothing is reachable.
  List<String> allowedDomains;

  /// ISO time of the last update check, so a launch does not hammer GitHub.
  String lastUpdateCheck;

  /// Answer word by word as it arrives. Off means one block when it is done.
  bool stream;

  /// How much of the transcript goes to the model each turn.
  int contextChars;

  /// Extra instructions appended to the built-in system prompt.
  String extraPrompt;

  /// 整个换掉的系统提示词。空着表示用内置那份。
  String systemPrompt;

  /// Transcript font size for answers.
  double answerFont;

  /// Ask GitHub for a newer release on launch.
  bool autoCheckUpdate;

  /// 前台通知长什么样：`simple` 一行、`big` 折开、`list` 一行一条、`chat` 像聊天。
  String notifStyle;

  static const List<String> notifStyles = <String>['simple', 'big', 'list', 'chat'];

  /// 记录长得太长时自己收成一段摘要。关掉就只在他点「压缩」时收。
  bool autoCompact;

  /// 开着的那几项扩展工具，见 `data/tool_groups.dart`。空着就一个都不给。
  List<String> enabledTools;

  /// 允许 AI 提参数调节。关掉之后它提了也不生效。
  bool aiTune;

  /// 用户在设置里改过的允许范围：`{temperature: [0, 1.2]}`。
  Map<String, List<double>> paramRanges;

  /// 这个参数现在允许落在什么范围里。
  ParamRange paramRange(String key) => paramRangeOf(key, overrides: paramRanges);

  bool toolOn(String id) => enabledTools.contains(id);

  /// 开或关一项。开关变了下一轮就生效，不用重开应用。
  void setTool(String id, bool on) {
    final List<String> next = List<String>.of(enabledTools)..remove(id);
    if (on) next.add(id);
    enabledTools = next;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'profiles': _profiles.map((ModelProfile p) => p.toJson()).toList(),
        'activeProfile': _active,
        // 老版本还认这两个，写的是当前这套的值。
        'baseUrl': baseUrl,
        'model': model,
        'temperature': temperature,
        'maxSteps': maxSteps,
        'approvalMode': approvalMode,
        'allowedDomains': allowedDomains,
        'lastUpdateCheck': lastUpdateCheck,
        'stream': stream,
        'contextChars': contextChars,
        'extraPrompt': extraPrompt,
        'systemPrompt': systemPrompt,
        'answerFont': answerFont,
        'autoCheckUpdate': autoCheckUpdate,
        'notifStyle': notifStyle,
        'autoCompact': autoCompact,
        'enabledTools': enabledTools,
        'aiTune': aiTune,
        if (paramRanges.isNotEmpty) 'paramRanges': paramRanges,
      };

  static AppSettings fromJson(Map<String, Object?> json) {
    final Object? domains = json['allowedDomains'];
    final Object? tools = json['enabledTools'];
    final Object? raw = json['profiles'];
    final List<ModelProfile> profiles = raw is List
        ? raw
            .whereType<Map<Object?, Object?>>()
            .map((Map<Object?, Object?> m) =>
                ModelProfile.fromJson(Map<String, Object?>.from(m)))
            .toList()
        : const <ModelProfile>[];
    return AppSettings(
      baseUrl: '${json['baseUrl'] ?? ''}',
      model: '${json['model'] ?? ''}',
      profiles: profiles,
      activeProfile: '${json['activeProfile'] ?? ''}',
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.2,
      maxSteps: (json['maxSteps'] as num?)?.toInt() ?? 12,
      approvalMode: '${json['approvalMode'] ?? 'autoRead'}',
      lastUpdateCheck: '${json['lastUpdateCheck'] ?? ''}',
      stream: json['stream'] != false,
      contextChars: (json['contextChars'] as num?)?.toInt() ?? 60000,
      extraPrompt: '${json['extraPrompt'] ?? ''}',
      systemPrompt: '${json['systemPrompt'] ?? ''}',
      answerFont: (json['answerFont'] as num?)?.toDouble() ?? 13.5,
      autoCheckUpdate: json['autoCheckUpdate'] != false,
      notifStyle: notifStyles.contains('${json['notifStyle'] ?? ''}')
          ? '${json['notifStyle']}'
          : 'simple',
      autoCompact: json['autoCompact'] != false,
      allowedDomains: domains is List
          ? domains.map((Object? e) => '$e').where((String s) => s.isNotEmpty).toList()
          : const <String>[],
      enabledTools: tools is List
          ? tools.map((Object? e) => '$e').where((String s) => s.isNotEmpty).toList()
          : const <String>[],
      aiTune: json['aiTune'] != false,
      paramRanges: _rangesOf(json['paramRanges']),
    );
  }

  /// `{temperature: [0, 1.2]}` 读回来。读不像样的直接丢掉。
  static Map<String, List<double>> _rangesOf(Object? raw) {
    final Map<String, List<double>> out = <String, List<double>>{};
    if (raw is! Map) return out;
    for (final MapEntry<Object?, Object?> e in raw.entries) {
      final Object? v = e.value;
      if (v is! List || v.length < 2) continue;
      final double? a = v[0] is num ? (v[0] as num).toDouble() : double.tryParse('${v[0]}');
      final double? b = v[1] is num ? (v[1] as num).toDouble() : double.tryParse('${v[1]}');
      if (a == null || b == null) continue;
      out['${e.key}'] = <double>[a, b];
    }
    return out;
  }
}

class SettingsStore {
  SettingsStore(this.file);

  final File file;
  AppSettings value = AppSettings();

  Future<void> load() async {
    if (!file.existsSync()) return;
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        value = AppSettings.fromJson(Map<String, Object?>.from(decoded));
      }
    } catch (_) {
      // keep the empty defaults
    }
  }

  Future<void> save() async {
    file.parent.createSync(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(value.toJson()));
  }

  /// 老版本只有一套配置，密钥记在 `model:apiKey` 上。
  /// 现在按配置各存一份，第一次启动时把老密钥搬到当前这套，搬完删掉老的。
  Future<void> migrateLegacyKey(SecretStore secrets) async {
    final String legacy = await secrets.read(modelSecretKey());
    if (legacy.isEmpty) return;
    final String target = modelSecretKeyFor(value.active.id);
    if ((await secrets.read(target)).isEmpty) {
      await secrets.write(target, legacy);
    }
    await secrets.delete(modelSecretKey());
  }
}
