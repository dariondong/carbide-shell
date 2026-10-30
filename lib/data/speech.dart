import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 长按输入框说话：系统的语音识别把话认成字，一句句送回来。
///
/// 只有 Android 有这一套；别的平台 [supported] 是 false，调用点不用分支。
/// 认出来的半成品先跟着话筒往输入框里长，收尾时再落定。
class Speech {
  Speech._();

  static const MethodChannel _channel = MethodChannel('top.theez.carbide_shell/speech');

  /// 现在是不是在听。界面上那个「正在听」看它。
  static final ValueNotifier<bool> listening = ValueNotifier<bool>(false);

  /// 这句话送给谁：每条结果都从这儿出去。
  static void Function(String text, bool done)? _onText;

  /// 认不出来时的原因，`permission` / `no-service` / `network` 之类。
  static void Function(String code)? _onError;

  static bool _wired = false;

  static bool get supported => Platform.isAndroid;

  /// 这台机器有没有能用的语音识别服务（问过一次就记着）。
  static Future<bool> available() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('available') == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 语音这一套在这台机器上走到哪一步：一行一条，诊断那一页看的就是它。
  static Future<List<String>> diag() async {
    if (!supported) return const <String>[];
    try {
      final List<Object?>? lines =
          await _channel.invokeMethod<List<Object?>>('diag');
      if (lines == null) return const <String>[];
      return lines.map((Object? e) => '$e').toList();
    } on MissingPluginException {
      return const <String>[];
    } on PlatformException {
      return const <String>[];
    }
  }

  /// 开始听。没有麦克风权限时会先要一次，要到了自己接着听。
  ///
  /// 返回 false 表示这次没起来（没服务、刚被系统掐掉、权限被拒）。
  static Future<bool> listen({
    required void Function(String text, bool done) onText,
    void Function(String code)? onError,
  }) async {
    if (!supported) return false;
    _wire();
    _onText = onText;
    _onError = onError;
    if (await _start()) return true;
    if (!await _grant()) {
      _onError?.call('permission');
      return false;
    }
    if (await _start()) return true;
    _onError?.call('no-service');
    return false;
  }

  /// 说完了：让识别服务把最后一句定下来。
  static Future<void> stop() => _call('stop');

  /// 不要了：这次就当没听。
  static Future<void> cancel() async {
    _onText = null;
    _onError = null;
    await _call('cancel');
  }

  /// 界面收起来了，别再往那边送字。
  static void forget() {
    _onText = null;
    _onError = null;
  }

  static Future<bool> _start() async {
    try {
      final Map<Object?, Object?>? map = await _channel
          .invokeMapMethod<Object?, Object?>('start');
      if (map == null) return false;
      return map['ok'] == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> _grant() async {
    try {
      return await _channel.invokeMethod<bool>('grant') == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> _call(String method) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // 没有原生那一段：当没这个能力。
    } on PlatformException {
      // 系统拦下了，不影响别的。
    }
  }

  static void _wire() {
    if (_wired) return;
    _wired = true;
    _channel.setMethodCallHandler((MethodCall call) async {
      final Map<Object?, Object?> args =
          (call.arguments as Map<Object?, Object?>?) ?? const <Object?, Object?>{};
      switch (call.method) {
        case 'text':
          _onText?.call('${args['text'] ?? ''}', args['done'] == true);
          break;
        case 'state':
          listening.value = args['on'] == true;
          break;
        case 'error':
          listening.value = false;
          final String code = '${args['code'] ?? 'error'}';
          // 没听到话、没认出来都不算错，别拿这个烦人。
          if (code != 'no-speech' && code != 'no-match') _onError?.call(code);
          break;
      }
      return null;
    });
  }
}
