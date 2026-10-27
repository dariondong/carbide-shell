import 'dart:convert';
import 'dart:io';

import 'secrets.dart';

/// 一套模型配置：地址、模型名、和界面上那个名字。
///
/// 密钥不在这里，按 [id] 存在安全存储里（见 [modelSecretKeyFor]）。
class ModelProfile {
  ModelProfile({
    required this.id,
    this.name = '',
    this.baseUrl = '',
    this.model = '',
  });

  String id;
  String name;
  String baseUrl;
  String model;

  /// 清单上写什么：自己起的名字优先，其次模型名，都没有就说没填。
  String get label {
    final String own = name.trim();
    if (own.isNotEmpty) return own;
    final String m = model.trim();
    return m.isEmpty ? '未填模型' : m;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'model': model,
      };

  static ModelProfile fromJson(Map<String, Object?> json) => ModelProfile(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        baseUrl: '${json['baseUrl'] ?? ''}',
        model: '${json['model'] ?? ''}',
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
      };

  static AppSettings fromJson(Map<String, Object?> json) {
    final Object? domains = json['allowedDomains'];
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
      allowedDomains: domains is List
          ? domains.map((Object? e) => '$e').where((String s) => s.isNotEmpty).toList()
          : const <String>[],
    );
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
