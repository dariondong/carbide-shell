import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/llm_base.dart';
import '../core/models.dart';
import '../core/openai.dart';
import 'secrets.dart';
import 'settings.dart';

/// 一套配置按 id 找；找不到就用现在默认的那套。
ModelProfile profileOf(AppSettings settings, String id) =>
    settings.profileById(id) ?? settings.active;

/// Reads the model settings on every call, so the settings page takes effect
/// without a restart.
///
/// 一场对话可以钉在自己选的那套配置上（见 [profileId]）：换配置不必先改全局。
class SettingsLlmProvider implements LlmProvider {
  SettingsLlmProvider(this.settings, this.secrets, {this.profileId});

  final SettingsStore settings;
  final SecretStore secrets;

  /// 这场对话用哪套配置。为空就是设置里选中的那套。
  final String Function()? profileId;

  ModelProfile get profile =>
      profileOf(settings.value, profileId?.call() ?? settings.value.activeProfile);

  @override
  String get label => profile.label;

  @override
  Future<LlmReply> chat({
    required String system,
    required List<LlmMessage> messages,
    required List<ToolSpec> tools,
    CancelToken? cancel,
    void Function(String delta)? onText,
  }) async {
    final ModelProfile chosen = profile;
    String key = await secrets.read(modelSecretKeyFor(chosen.id));
    // 老的单一密钥只在还没搬过来之前顶一下。
    if (key.isEmpty) key = await secrets.read(modelSecretKey());
    final OpenAiProvider provider = OpenAiProvider(
      baseUrl: chosen.baseUrl,
      apiKey: key,
      model: chosen.model,
      temperature: settings.value.temperatureFor(chosen),
    );
    try {
      return await provider.chat(
        system: system,
        messages: messages,
        tools: tools,
        cancel: cancel,
        // 关掉逐字显示就不传 onText：服务端一次性回，界面等整段。
        onText: settings.value.stream ? onText : null,
      );
    } finally {
      provider.close();
    }
  }
}

class SecureSecretStore implements SecretStore {
  const SecureSecretStore([this.storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage storage;

  @override
  Future<String> read(String key) async {
    try {
      return await storage.read(key: key) ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await storage.write(key: key, value: value);
    } catch (_) {
      // A device without a keystore still lets the app run.
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await storage.delete(key: key);
    } catch (_) {
      // ignore
    }
  }
}

String describePlatform() {
  if (Platform.isAndroid) return 'Android';
  if (Platform.isIOS) return 'iOS';
  if (Platform.isWindows) return 'Windows';
  if (Platform.isMacOS) return 'macOS';
  if (Platform.isLinux) return 'Linux';
  return 'unknown';
}

bool get isDesktopPlatform =>
    !Platform.isAndroid && !Platform.isIOS;

String decodeUtf8(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);
