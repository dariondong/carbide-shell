import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/asr.dart';

/// 长按说话走哪一条，以及在线识别要的那几个参数。
///
/// 系统引擎在有的机器上根本拉不起来（一直回 ERROR_CLIENT），所以除了它还有两条：
/// 叫起系统自带的认字界面，或者自己录一段交给网上的接口。
class SpeechConfig {
  const SpeechConfig({
    this.mode = 'system',
    this.baseUrl = '',
    this.model = '',
    this.key = _noKey,
  });

  /// `system` / `systemInput` / `cloud`，与 `AppSettings.asrModes` 一套。
  final String mode;

  final String baseUrl;
  final String model;

  /// 密钥现取：它存在安全存储里，读一次要 await。
  final Future<String> Function() key;

  bool get cloudReady =>
      baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  static Future<String> _noKey() async => '';
}

/// 长按输入框说话：把话认成字，一句句送回来。
///
/// 三种走法共用一个入口 [listen]，界面那边不用分支；只有 Android 有这一套，
/// 别的平台 [supported] 是 false。
class Speech {
  Speech._();

  static const MethodChannel _channel = MethodChannel('top.theez.carbide_shell/speech');

  /// 现在是不是在听。界面上那个「正在听」看它。
  static final ValueNotifier<bool> listening = ValueNotifier<bool>(false);

  /// 输入框上方那一行小字：正听着说「正在听」，没认出来时说一句为什么。
  ///
  /// 走的是这一行字而不是弹窗：长按说话本来就是手上的动作，屏幕上再弹一条挡着更烦。
  static final ValueNotifier<String> hint = ValueNotifier<String>('');

  static const String _listeningText = '正在听，松手结束';

  static Timer? _clearHint;

  /// 最近一次认出来的字，诊断那一段看它。
  static String lastText = '';

  /// 最近一次出错的原因，诊断那一段看它。
  static String lastError = '';

  static SpeechConfig _config = const SpeechConfig();

  /// 在录音（在线识别那条）。松手可能比录音起来得早，所以这两个分开记。
  static bool _recording = false;
  static bool _stopAsked = false;

  /// 一段录音最长多久。真忘了松手也不会把麦克风占着。
  static Timer? _cap;

  /// 设置变了就调一次：下一次长按按新的走。
  static void configure(SpeechConfig config) => _config = config;

  static SpeechConfig get config => _config;

  /// 改那一行字。[hold] 之后自己收起来，0 表示一直留着。
  static void _say(String text, {Duration hold = const Duration(seconds: 3)}) {
    _clearHint?.cancel();
    _clearHint = null;
    hint.value = text;
    if (text.isEmpty || hold == Duration.zero) return;
    _clearHint = Timer(hold, () {
      if (hint.value == text) hint.value = '';
    });
  }

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
    final List<String> out = <String>[];
    out.add('识别方式：${_modeName(_config.mode)}');
    if (_config.mode == 'cloud') {
      out.add('在线地址：${_config.baseUrl.trim().isEmpty ? '没填' : _config.baseUrl.trim()}');
      out.add('在线模型：${_config.model.trim().isEmpty ? '没填' : _config.model.trim()}');
      out.add('接口地址：${asrEndpoint(_config.baseUrl).isEmpty ? '没填' : asrEndpoint(_config.baseUrl)}');
      String secret = '';
      try {
        secret = (await _config.key()).trim();
      } catch (_) {
        secret = '';
      }
      out.add('在线密钥：${secret.isEmpty ? '没填' : '填了'}');
    }
    out.add('上次认出的字：${lastText.isEmpty ? '还没有' : lastText}');
    if (lastError.isNotEmpty) out.add('上次的错：$lastError');
    try {
      final List<Object?>? lines =
          await _channel.invokeMethod<List<Object?>>('diag');
      if (lines != null) {
        out.addAll(lines.map((Object? e) => '$e'));
      }
    } on MissingPluginException {
      // 没有原生那一段：前面那几行照样有用。
    } on PlatformException {
      // 同上。
    }
    return out;
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
    switch (_config.mode) {
      case 'cloud':
        if (!_config.cloudReady) {
          _fail('cloud-off');
          return false;
        }
        return _listenCloud();
      case 'systemInput':
        return _listenSystemInput();
    }
    if (await _start()) return true;
    if (!await _grant()) {
      _fail('permission');
      return false;
    }
    if (await _start()) return true;
    _fail('no-service');
    return false;
  }

  /// 说完了：让识别服务把最后一句定下来。
  static Future<void> stop() async {
    if (!supported) return;
    if (_config.mode == 'cloud') {
      _stopAsked = true;
      if (_recording) await _finishCloud();
      return;
    }
    await _call('stop');
  }

  /// 不要了：这次就当没听。
  static Future<void> cancel() async {
    _onText = null;
    _onError = null;
    if (_config.mode == 'cloud') {
      listening.value = false;
      _recording = false;
      _stopAsked = false;
      _cap?.cancel();
      await _call('recordCancel');
      if (hint.value == _listeningText) _say('');
      return;
    }
    await _call('cancel');
  }

  /// 界面收起来了，别再往那边送字。
  static void forget() {
    _onText = null;
    _onError = null;
  }

  /// 试一句：录 [span] 那么久，交给在线识别认一次，回一句人话。
  ///
  /// 设置页那个「试一句」用它，不经过长按手势。
  static Future<String> probe({
    SpeechConfig? config,
    Duration span = const Duration(seconds: 3),
  }) async {
    if (!supported) return '这台机器上没有这一套';
    final SpeechConfig cfg = config ?? _config;
    if (!cfg.cloudReady) return '地址或模型没填';
    if (_recording) {
      await _call('recordCancel');
      _recording = false;
    }
    if (!await _record('recordStart')) {
      if (!await _grant()) return '没有麦克风权限';
      if (!await _record('recordStart')) return '录音起不来';
    }
    _recording = true;
    await Future<void>.delayed(span);
    _recording = false;
    final AsrResult result = await _upload(cfg);
    if (result.ok) return '认出来了：${result.text}';
    return result.error == 'no-match'
        ? '没录到声音，再说一次'
        : '没认出来：${result.error}';
  }

  /// 在线识别：自己录，松手之后把 wav 交给网上的接口。
  static Future<bool> _listenCloud() async {
    _stopAsked = false;
    if (!await _record('recordStart')) {
      if (!await _grant()) {
        _fail('permission');
        return false;
      }
      if (!await _record('recordStart')) {
        _fail('record');
        return false;
      }
    }
    _recording = true;
    listening.value = true;
    _say(_listeningText, hold: const Duration(minutes: 5));
    _cap?.cancel();
    _cap = Timer(const Duration(seconds: 120), () {
      if (_recording) stop();
    });
    // 手已经松开、但录音刚刚才起来：直接收尾，别把麦克风晾着。
    if (_stopAsked) await _finishCloud();
    return true;
  }

  static Future<void> _finishCloud() async {
    _recording = false;
    _stopAsked = false;
    _cap?.cancel();
    listening.value = false;
    _say('正在认字…', hold: const Duration(seconds: 30));
    final AsrResult result = await _upload(_config);
    if (result.ok) {
      lastText = result.text;
      _say('');
      _onText?.call(result.text, true);
      return;
    }
    if (result.error == 'no-match') {
      _fail('no-match');
      return;
    }
    _fail('cloud-fail', detail: result.error);
  }

  /// 收尾录音并上传。录音文件用过就删。
  static Future<AsrResult> _upload(SpeechConfig cfg) async {
    String path = '';
    try {
      path = await _channel.invokeMethod<String>('recordStop') ?? '';
    } on MissingPluginException {
      return const AsrResult('', '没有录音这一段');
    } on PlatformException catch (error) {
      return AsrResult('', '录音收尾失败：${error.message}');
    }
    if (path.isEmpty) return const AsrResult('', 'no-match');
    List<int> wav = const <int>[];
    try {
      wav = await File(path).readAsBytes();
    } catch (error) {
      wav = const <int>[];
    }
    try {
      await File(path).delete();
    } catch (_) {
      // 删不掉就留着，缓存目录本来也会被系统清。
    }
    if (wav.isEmpty) return const AsrResult('', 'no-match');
    String key = '';
    try {
      key = await cfg.key();
    } catch (_) {
      key = '';
    }
    return transcribeWav(
      wav: wav,
      baseUrl: cfg.baseUrl,
      model: cfg.model,
      key: key,
    );
  }

  /// 叫起系统自带的认字界面，认完把字接回来。
  static Future<bool> _listenSystemInput() async {
    _say('说一句，认完自己回来', hold: const Duration(seconds: 40));
    String text = '';
    try {
      text = await _channel.invokeMethod<String>('systemInput') ?? '';
    } on MissingPluginException {
      _say('');
      _fail('no-service');
      return false;
    } on PlatformException {
      _say('');
      _fail('no-service');
      return false;
    }
    if (text.trim().isEmpty) {
      _say('');
      _fail('cancel');
      return false;
    }
    lastText = text.trim();
    _say('');
    _onText?.call(text.trim(), true);
    return true;
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

  static Future<bool> _record(String method) async {
    try {
      final Map<Object?, Object?>? map =
          await _channel.invokeMapMethod<Object?, Object?>(method);
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

  /// 出一趟错：写清是哪一环，界面那行小字也说一句。
  static void _fail(String code, {String detail = ''}) {
    listening.value = false;
    lastError = detail.isEmpty ? code : '$code：$detail';
    _say(_note(code));
    _onError?.call(code);
  }

  static String _note(String code) => switch (code) {
        'no-match' || 'no-speech' => '没听清，再按一次',
        'permission' => '没有麦克风权限',
        'no-service' => '这台机器没有语音识别服务',
        'network' => '语音识别要联网，这次没连上',
        'busy' => '识别服务正忙着，等一下再说',
        'cancel' => '这次没说话',
        'cloud-off' => '在线识别还没填地址和模型',
        'cloud-fail' => '在线识别没成功，设置里的诊断能看细的',
        'record' => '录音起不来，换一种识别方式试试',
        _ => '识别没起来（$code）',
      };

  static String _modeName(String mode) => switch (mode) {
        'cloud' => '在线识别',
        'systemInput' => '系统认字界面',
        _ => '系统识别',
      };

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
          final bool on = args['on'] == true;
          listening.value = on;
          if (on) {
            _say(_listeningText, hold: const Duration(minutes: 5));
          } else if (hint.value == _listeningText) {
            _say('');
          }
          break;
        case 'error':
          listening.value = false;
          final String code = '${args['code'] ?? 'error'}';
          lastError = code;
          // 没听到话不算错，只说一句「没听清」；别的原因把代号一起写出来，
          // 真出问题时看一眼就知道是哪一环。
          _say(_note(code));
          _onError?.call(code);
          break;
      }
      return null;
    });
  }
}
