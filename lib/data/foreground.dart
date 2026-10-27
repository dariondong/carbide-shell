import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 这台机器现在能不能弹通知：系统总开关，加上安卓 13 起的那个权限。
class NotifyState {
  const NotifyState({this.allowed = true, this.granted = true});

  /// 系统设置里允许这个应用发通知。
  final bool allowed;

  /// 安卓 13 起要单独允许的 POST_NOTIFICATIONS。
  final bool granted;

  bool get ready => allowed && granted;

  String get text {
    if (ready) return '开着';
    if (!allowed) return '系统里被关掉了';
    return '还没允许';
  }
}

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
  ///
  /// [style] 是通知长什么样（`simple` / `big` / `list` / `chat`），
  /// [lines] 是最近说过的几句，大文本和会话样式拿它铺开。
  static Future<void> begin(
    String text, {
    String style = 'simple',
    List<String> lines = const <String>[],
  }) =>
      _call('begin', text, style: style, lines: lines);

  /// 跑完了，把通知收掉。
  static Future<void> end() => _call('end', '');

  /// 换通知上那句话。服务没起来就等于再 begin 一次。
  static Future<void> update(String text, {List<String> lines = const <String>[]}) =>
      _call('update', text, lines: lines);

  /// 跑完了，把通知收掉。人不在这个应用里时留一条「跑完了」，点一下回来。
  static Future<void> finish(
    String text, {
    String style = 'simple',
    List<String> lines = const <String>[],
  }) =>
      _call('finish', text, style: style, lines: lines);

  /// 一条提示：不常驻，点一下回到应用。资源监听过线、模型要提醒人时用。
  ///
  /// [slot] 是它占的那一格：同一个格子的后一条盖掉前一条，不同格子并排留着。
  /// 不写就是 0，一直用同一个位置。
  static Future<void> alert(String title, String text, {int slot = 0}) =>
      _call('alert', text, title: title, slot: slot);

  /// 系统的省电与后台限制那一页。有的系统会连服务一起清掉，这一项让用户自己放开。
  static Future<void> openBatterySettings() => _call('battery', '');

  /// 通知渠道建出来，顺带拿一眼现在能不能发。
  static Future<NotifyState> prepare() async => supported ? await state() : const NotifyState();

  /// 现在能不能发通知。桌面和测试环境当作能。
  static Future<NotifyState> state() async {
    if (!supported) return const NotifyState();
    final Map<Object?, Object?>? map = await _ask('notifyState');
    if (map == null) return const NotifyState();
    return NotifyState(
      allowed: map['allowed'] != false,
      granted: map['granted'] != false,
    );
  }

  /// 主动要一次通知权限。
  static Future<NotifyState> request() async {
    if (!supported) return const NotifyState();
    final Map<Object?, Object?>? map = await _ask('request');
    if (map == null) return const NotifyState();
    return NotifyState(
      allowed: map['allowed'] != false,
      granted: map['granted'] != false,
    );
  }

  /// 系统的通知设置页。权限拒过之后只能在这里打开。
  static Future<void> openNotificationSettings() => _call('notifSettings', '');

  /// 问原生要一个 map，原生那段不在就当没有。
  static Future<Map<Object?, Object?>?> _ask(String method) async {
    try {
      return await _channel.invokeMapMethod<Object?, Object?>(method);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// 应用现在是不是在前台。取不到生命周期就当作在前台。
  static bool get visible {
    try {
      final AppLifecycleState? state = WidgetsBinding.instance.lifecycleState;
      return state == null || state == AppLifecycleState.resumed;
    } catch (_) {
      return true;
    }
  }

  static Future<void> _call(
    String method,
    String text, {
    String title = '',
    int slot = 0,
    String style = '',
    List<String> lines = const <String>[],
  }) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>(
        method,
        <String, Object?>{
          'text': text,
          'title': title,
          'slot': slot,
          'style': style,
          'lines': lines,
        },
      );
    } on MissingPluginException {
      // 没有原生那一段（桌面、测试环境）：当没这个能力。
    } on PlatformException {
      // 系统拦下了这次调用，任务本身不受影响。
    }
  }
}
