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

  Map<String, Object?> toJson() => <String, Object?>{
        'baseUrl': baseUrl,
        'model': model,
        'temperature': temperature,
        'maxSteps': maxSteps,
        'approvalMode': approvalMode,
        'allowedDomains': allowedDomains,
        'lastUpdateCheck': lastUpdateCheck,
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
