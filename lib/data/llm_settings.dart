import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/llm_base.dart';
import '../core/models.dart';
import '../core/openai.dart';
import 'secrets.dart';
import 'settings.dart';

/// Reads the model settings on every call, so the settings page takes effect
/// without a restart.
class SettingsLlmProvider implements LlmProvider {
  SettingsLlmProvider(this.settings, this.secrets);

  final SettingsStore settings;
  final SecretStore secrets;

  @override
  String get label => settings.value.active.label;

  @override
  Future<LlmReply> chat({
    required String system,
    required List<LlmMessage> messages,
    required List<ToolSpec> tools,
    CancelToken? cancel,
    void Function(String delta)? onText,
  }) async {
    final ModelProfile profile = settings.value.active;
    String key = await secrets.read(modelSecretKeyFor(profile.id));
    // 老的单一密钥只在还没搬过来之前顶一下。
    if (key.isEmpty) key = await secrets.read(modelSecretKey());
    final OpenAiProvider provider = OpenAiProvider(
      baseUrl: profile.baseUrl,
      apiKey: key,
      model: profile.model,
      temperature: settings.value.temperature,
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
