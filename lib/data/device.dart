import 'dart:io';

import 'package:flutter/services.dart';

import '../core/phone_signals.dart';

export '../core/phone_signals.dart';

/// 手机这一侧的几件事：设备信息、位置、联系人、短信、分享。
///
/// 只有安卓有这条原生通道。别的平台上 [supported] 是 false，
/// 调用点如实说这里没有，不假装做过。
const MethodChannel _channel = MethodChannel('top.theez.carbide_shell/device');

/// 要单独向系统申请的权限。
enum DevicePerm { sms, location, contacts, notification, usageAccess }

extension DevicePermInfo on DevicePerm {
  /// 原生那边认的代号。
  String get code => switch (this) {
        DevicePerm.sms => 'sms',
        DevicePerm.location => 'location',
        DevicePerm.contacts => 'contacts',
        DevicePerm.notification => 'notif',
        DevicePerm.usageAccess => 'usage',
      };

  /// 设置在界面上的名字。
  String get label => switch (this) {
        DevicePerm.sms => '短信',
        DevicePerm.location => '位置',
        DevicePerm.contacts => '联系人',
        DevicePerm.notification => '通知读取',
        DevicePerm.usageAccess => '使用情况访问',
      };
}

/// 原生那边出不来时抛出的一句话，工具原样交给模型。
class DeviceError implements Exception {
  const DeviceError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 这台手机现在什么样子。拿不到的项留空或者 -1。
class DeviceInfo {
  const DeviceInfo({
    this.model = '',
    this.brand = '',
    this.sdk = 0,
    this.abi = '',
    this.battery = -1,
    this.charging = false,
    this.network = '',
    this.freeMb = 0,
    this.totalMb = 0,
  });

  factory DeviceInfo.fromMap(Map<Object?, Object?> m) => DeviceInfo(
        model: '${m['model'] ?? ''}',
        brand: '${m['brand'] ?? ''}',
        sdk: (m['sdk'] as num?)?.toInt() ?? 0,
        abi: '${m['abi'] ?? ''}',
        battery: (m['battery'] as num?)?.toInt() ?? -1,
        charging: m['charging'] == true,
        network: '${m['network'] ?? ''}',
        freeMb: (m['freeMb'] as num?)?.toInt() ?? 0,
        totalMb: (m['totalMb'] as num?)?.toInt() ?? 0,
      );

  final String model;
  final String brand;
  final int sdk;
  final String abi;
  final int battery;
  final bool charging;
  final String network;
  final int freeMb;
  final int totalMb;

  /// 一行一件事，给模型看的那几句。
  String render() {
    final String name = '$brand $model'.trim();
    final List<String> lines = <String>[
      if (name.isNotEmpty) '机型：$name${sdk > 0 ? '（安卓 $sdk${abi.isEmpty ? '' : '，$abi'}）' : ''}',
      if (battery >= 0) '电量：$battery%${charging ? '，在充电' : ''}',
      if (network.isNotEmpty) '网络：${networkName(network)}',
      if (totalMb > 0) '存储：剩 $freeMb MB，共 $totalMb MB',
    ];
    return lines.join('\n');
  }
}

/// 最近一次定位。
class DeviceFix {
  const DeviceFix({
    required this.lat,
    required this.lng,
    this.accuracy = 0,
    this.provider = '',
    this.at,
  });

  factory DeviceFix.fromMap(Map<Object?, Object?> m) {
    final int ms = (m['at'] as num?)?.toInt() ?? 0;
    return DeviceFix(
      lat: (m['lat'] as num?)?.toDouble() ?? 0,
      lng: (m['lng'] as num?)?.toDouble() ?? 0,
      accuracy: (m['accuracy'] as num?)?.toDouble() ?? 0,
      provider: '${m['provider'] ?? ''}',
      at: ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms) : null,
    );
  }

  final double lat;
  final double lng;
  final double accuracy;
  final String provider;
  final DateTime? at;

  String render(DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    final String point =
        '纬度 ${lat.toStringAsFixed(5)}，经度 ${lng.toStringAsFixed(5)}';
    final String err = accuracy > 0 ? '误差约 ${accuracy.round()} 米' : '';
    final DateTime? t = at;
    String age = '';
    if (t != null) {
      final int min = now.difference(t).inMinutes;
      age = min <= 0 ? '刚刚' : '$min 分钟前';
    }
    final String when =
        age.isNotEmpty ? age : (t != null ? '${two(t.hour)}:${two(t.minute)}' : '');
    return <String>[point, err, when].where((String s) => s.isNotEmpty).join('，');
  }
}

/// 收到的一条通知。正文里带长文本时取那一段。
class DeviceNotification {
  const DeviceNotification({
    this.app = '',
    this.pkg = '',
    this.title = '',
    this.text = '',
    this.at,
  });

  factory DeviceNotification.fromMap(Map<Object?, Object?> m) {
    final int ms = (m['at'] as num?)?.toInt() ?? 0;
    return DeviceNotification(
      app: '${m['app'] ?? ''}',
      pkg: '${m['pkg'] ?? ''}',
      title: '${m['title'] ?? ''}',
      text: '${m['text'] ?? ''}',
      at: ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms) : null,
    );
  }

  final String app;
  final String pkg;
  final String title;
  final String text;
  final DateTime? at;

  /// 一行一条：时间、应用、标题加正文。
  String get line {
    final DateTime? t = at;
    String when = '';
    if (t != null) {
      final DateTime local = t.toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      when = '${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)} ';
    }
    final String who = app.isEmpty ? pkg : app;
    final String head = title.trim();
    final String body = text.trim();
    final String said = head.isEmpty
        ? body
        : (body.isEmpty ? head : '$head：$body');
    return '$when$who $said';
  }
}

/// 一个应用最近用了多久。
class AppUsage {
  const AppUsage({this.app = '', this.pkg = '', this.minutes = 0, this.last});

  factory AppUsage.fromMap(Map<Object?, Object?> m) {
    final int ms = (m['last'] as num?)?.toInt() ?? 0;
    return AppUsage(
      app: '${m['app'] ?? ''}',
      pkg: '${m['pkg'] ?? ''}',
      minutes: (m['minutes'] as num?)?.toInt() ?? 0,
      last: ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms) : null,
    );
  }

  final String app;
  final String pkg;
  final int minutes;
  final DateTime? last;

  /// 「1 小时 5 分」这种。
  String get span {
    if (minutes < 60) return '$minutes 分钟';
    final int h = minutes ~/ 60;
    final int m = minutes % 60;
    return m == 0 ? '$h 小时' : '$h 小时 $m 分';
  }

  String get line => '${app.isEmpty ? pkg : app}\t$span';
}

/// 一条联系人：名字加一个号码。
class DeviceContact {  const DeviceContact({required this.name, required this.phone});

  factory DeviceContact.fromMap(Map<Object?, Object?> m) => DeviceContact(
        name: '${m['name'] ?? ''}'.trim(),
        phone: '${m['phone'] ?? ''}'.trim(),
      );

  final String name;
  final String phone;

  String get line => name.isEmpty ? phone : '$name $phone';
}

/// 打开这个应用在系统里的那一页。权限被拒过之后，只能去那里改。
/// 别的平台什么都不做。
Future<void> openAppSettings() async {
  if (!Platform.isAndroid) return;
  try {
    await _channel.invokeMethod<Object?>('appSettings');
  } on MissingPluginException {
    // 没有这条通道就算了，用户自己去系统设置里找。
  } on PlatformException {
    // 系统没接住也不报错，这一下本来就是帮忙。
  }
}

/// 手机能力的入口。测试里换成假的，工具就不用碰原生。
abstract class DeviceApi {
  const DeviceApi();

  /// 这台机器有没有手机那一套。桌面和网页没有。
  bool get supported;

  Future<DeviceInfo> info();

  /// 手机此刻的状态信号：充电、电量、网络、亮屏、锁屏、耳机、铃音、勿扰、在放音乐。
  /// 系统不给的那几项（比如驾驶状态）不会出现。
  Future<PhoneSignals> phoneState();

  Future<bool> has(DevicePerm perm);

  Future<bool> request(DevicePerm perm);

  /// 最近一次定位。系统里还没有就返回 null。
  Future<DeviceFix?> location();

  Future<List<DeviceContact>> contacts({String query = '', int limit = 20});

  Future<void> sendSms(String to, String text);

  Future<void> share(String text, {String subject = ''});

  Future<String> clipboard();

  Future<void> setClipboard(String text);

  /// 最近收到的通知。没有「通知使用权」时抛 [DeviceError]。
  Future<List<DeviceNotification>> notifications({int limit = 40, int minutes = 720});

  /// 每个应用最近用了多久。没有「使用情况访问」时抛 [DeviceError]。
  Future<List<AppUsage>> usage({int hours = 24});

  /// 去系统里那两页。应用不能替用户打开这两项。
  Future<void> openNotificationAccess();

  Future<void> openUsageAccess();
}

/// 真的那一个：走原生通道。剪贴板用 Flutter 自带的那套。
class PhoneDevice implements DeviceApi {
  const PhoneDevice();

  @override
  bool get supported => Platform.isAndroid;

  @override
  Future<DeviceInfo> info() async =>
      DeviceInfo.fromMap(_map(await _call('info')));

  @override
  Future<PhoneSignals> phoneState() async {
    final Object? raw = await _call('phoneState');
    if (raw is! Map) return const PhoneSignals();
    return PhoneSignals.fromMap(raw);
  }

  @override
  Future<bool> has(DevicePerm perm) async =>
      await _call('has', <String, Object?>{'perm': perm.code}) == true;

  @override
  Future<bool> request(DevicePerm perm) async =>
      await _call('request', <String, Object?>{'perm': perm.code}) == true;

  @override
  Future<DeviceFix?> location() async {
    final Object? raw = await _call('location');
    if (raw is! Map) return null;
    return DeviceFix.fromMap(raw);
  }

  @override
  Future<List<DeviceContact>> contacts({String query = '', int limit = 20}) async {
    final Object? raw = await _call('contacts', <String, Object?>{
      'query': query,
      'limit': limit,
    });
    if (raw is! List) return const <DeviceContact>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(DeviceContact.fromMap)
        .where((DeviceContact c) => c.phone.isNotEmpty)
        .toList();
  }

  @override
  Future<void> sendSms(String to, String text) =>
      _call('sms', <String, Object?>{'to': to, 'text': text});

  @override
  Future<void> share(String text, {String subject = ''}) =>
      _call('share', <String, Object?>{'text': text, 'subject': subject});

  @override
  Future<String> clipboard() async {
    try {
      final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
      return data?.text ?? '';
    } catch (e) {
      throw DeviceError('读不到剪贴板：$e');
    }
  }

  @override
  Future<void> setClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (e) {
      throw DeviceError('写不进剪贴板：$e');
    }
  }

  @override
  Future<List<DeviceNotification>> notifications({
    int limit = 40,
    int minutes = 720,
  }) async {
    final Object? raw = await _call('notifs', <String, Object?>{
      'limit': limit,
      'minutes': minutes,
    });
    if (raw is! List) return const <DeviceNotification>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(DeviceNotification.fromMap)
        .toList();
  }

  @override
  Future<List<AppUsage>> usage({int hours = 24}) async {
    final Object? raw = await _call('usage', <String, Object?>{'hours': hours});
    if (raw is! List) return const <AppUsage>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(AppUsage.fromMap)
        .toList();
  }

  @override
  Future<void> openNotificationAccess() =>
      _call('openNotifAccess', <String, Object?>{});

  @override
  Future<void> openUsageAccess() => _call('openUsageAccess', <String, Object?>{});

  Future<Object?> _call(String method, [Map<String, Object?>? args]) async {    if (!supported) throw const DeviceError('这台机器上没有手机那一套，只有安卓上才有。');
    try {
      return await _channel.invokeMethod<Object?>(method, args);
    } on MissingPluginException {
      throw const DeviceError('这台机器上没有手机那一套，只有安卓上才有。');
    } on PlatformException catch (e) {
      throw DeviceError(e.message ?? e.code);
    }
  }

  Map<Object?, Object?> _map(Object? raw) =>
      raw is Map ? raw : const <Object?, Object?>{};
}
