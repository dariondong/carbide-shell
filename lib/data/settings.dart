import 'dart:convert';
import 'dart:io';

/// Everything the user typed on the settings page. No default address.
class AppSettings {
  AppSettings({
    this.baseUrl = '',
    this.model = '',
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
  });

  String baseUrl;
  String model;
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
    return AppSettings(
      baseUrl: '${json['baseUrl'] ?? ''}',
      model: '${json['model'] ?? ''}',
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
}
