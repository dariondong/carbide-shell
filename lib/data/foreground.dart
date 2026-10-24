import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 跑长任务时挂一条前台通知，切出去、锁屏都还在跑。
///
/// 只有 Android 有这一套；别的平台这几个方法什么都不做，调用点不用分支。
/// 原生那边起不来（没权限、被后台限制）时也只当没这回事：任务本身照常跑完。
class ForegroundTask {
  ForegroundTask._();

  static const MethodChannel _channel =
      MethodChannel('top.theez.carbide_shell/foreground');

  /// 这台机器有没有这一套（现在只有 Android 有）。
  static bool get supported => Platform.isAndroid;

  /// 开始跑：通知上写现在在干什么。
  static Future<void> begin(String text) => _call('begin', text);

  /// 跑完了，把通知收掉。
  static Future<void> end() => _call('end', '');

  /// 换通知上那句话。服务没起来就等于再 begin 一次。
  static Future<void> update(String text) => _call('update', text);

  /// 跑完了，把通知收掉。人不在这个应用里时留一条「跑完了」，点一下回来。
  static Future<void> finish(String text) => _call('finish', text);

  /// 系统的省电与后台限制那一页。有的系统会连服务一起清掉，这一项让用户自己放开。
  static Future<void> openBatterySettings() => _call('battery', '');

  /// 应用现在是不是在前台。取不到生命周期就当作在前台。
  static bool get visible {
    try {
      final AppLifecycleState? state = WidgetsBinding.instance.lifecycleState;
      return state == null || state == AppLifecycleState.resumed;
    } catch (_) {
      return true;
    }
  }

  static Future<void> _call(String method, String text) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>(method, <String, Object?>{'text': text});
    } on MissingPluginException {
      // 没有原生那一段（桌面、测试环境）：当没这个能力。
    } on PlatformException {
      // 系统拦下了这次调用，任务本身不受影响。
    }
  }
}
