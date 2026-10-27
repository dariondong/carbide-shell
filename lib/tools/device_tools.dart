import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';
import '../core/tools.dart';
import '../data/device.dart';

/// 手机上的这几个工具，用户先在设置里把对应的扩展打开才会进清单。
///
/// 每一条都先看权限。没有权限就如实说去设置里打开，不自己弹框，
/// 也不假装做过了。

String _short(String text, [int max = 40]) {
  final String one = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (one.length <= max) return one;
  return '${one.substring(0, max)}…';
}

/// `device_info`：机型、电量、网络、剩余存储。不要权限。
class DeviceInfoTool extends Tool {
  DeviceInfoTool(this.device);

  final DeviceApi device;

  @override
  String get name => 'device_info';

  @override
  String get description =>
      '看这台手机现在什么样子：机型、安卓版本、电量、网络、剩余存储。'
      '不要权限。判断「手机还剩多少电」「现在走的是无线还是流量」用这个。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
        'required': <String>[],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.read;

  @override
  String summarize(Map<String, Object?> args) => '看手机的电量和网络';

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    try {
      final String text = (await device.info()).render();
      return ToolOutcome.success(stdout: text.isEmpty ? '这台机器报不出什么信息。' : text);
    } on DeviceError catch (e) {
      return ToolOutcome.failure(e.message);
    }
  }
}

/// `clipboard`：读一段、写一段。
class ClipboardTool extends Tool {
  ClipboardTool(this.device);

  final DeviceApi device;

  @override
  String get name => 'clipboard';

  @override
  String get description =>
      '读写这台手机的剪贴板。action 写 read 就把剪贴板里的文字取回来，'
      '写 write 就把 text 放进去。安卓 10 起系统不让后台读剪贴板，读回空的就说空了。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'action': <String, Object?>{
            'type': 'string',
            'enum': <String>['read', 'write'],
            'description': 'read 读出来，write 放进去',
          },
          'text': <String, Object?>{
            'type': 'string',
            'description': 'action 是 write 时写进去的内容',
          },
        },
        'required': <String>['action'],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) =>
      readString(args, 'action', fallback: 'read') == 'write' ? ToolRisk.write : ToolRisk.read;

  @override
  String summarize(Map<String, Object?> args) {
    if (readString(args, 'action', fallback: 'read') != 'write') return '读剪贴板';
    return '写进剪贴板：${_short(readString(args, 'text'))}';
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String action = readString(args, 'action', fallback: 'read');
    try {
      if (action == 'write') {
        final String text = readString(args, 'text');
        if (text.isEmpty) return const ToolOutcome.failure('要写什么得放在 text 里。');
        await device.setClipboard(text);
        return ToolOutcome.success(stdout: '写进剪贴板了：${_short(text)}');
      }
      final String text = await device.clipboard();
      if (text.trim().isEmpty) {
        return const ToolOutcome.success(stdout: '剪贴板里没有文字，或者系统不让后台读。');
      }
      return ToolOutcome.success(stdout: text);
    } on DeviceError catch (e) {
      return ToolOutcome.failure(e.message);
    }
  }
}

/// `open_url`：交给浏览器。
class OpenUrlTool extends Tool {
  OpenUrlTool();

  @override
  String get name => 'open_url';

  @override
  String get description =>
      '用手机上的浏览器打开一个网址。只认 http 和 https。'
      '要让用户看的东西在网页上时用这个，别把整页内容抄进回答。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'url': <String, Object?>{'type': 'string', 'description': '完整的网址'},
        },
        'required': <String>['url'],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.write;

  @override
  String summarize(Map<String, Object?> args) => '用浏览器打开 ${readString(args, 'url')}';

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String raw = readString(args, 'url').trim();
    if (raw.isEmpty) return const ToolOutcome.failure('网址是空的。');
    final Uri? uri = Uri.tryParse(raw);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return const ToolOutcome.failure('只开 http 和 https 的地址。');
    }
    try {
      final bool opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) return ToolOutcome.failure('系统没接住这个地址：$raw');
      return ToolOutcome.success(stdout: '交给浏览器了：$raw');
    } catch (e) {
      return ToolOutcome.failure('打不开这个地址：$e');
    }
  }
}

/// `share_text`：交给系统的分享面板。
class ShareTool extends Tool {
  ShareTool(this.device);

  final DeviceApi device;

  @override
  String get name => 'share_text';

  @override
  String get description =>
      '把一段话交给系统的分享面板，用户自己挑发给谁。'
      '要用户把结果转给别人时用这个，不要自己编收件人。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'text': <String, Object?>{'type': 'string', 'description': '要分享出去的内容'},
          'subject': <String, Object?>{'type': 'string', 'description': '标题，可以不写'},
        },
        'required': <String>['text'],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.write;

  @override
  String summarize(Map<String, Object?> args) => '分享：${_short(readString(args, 'text'))}';

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String text = readString(args, 'text');
    if (text.trim().isEmpty) return const ToolOutcome.failure('要分享什么得放在 text 里。');
    try {
      await device.share(text, subject: readString(args, 'subject').trim());
      return const ToolOutcome.success(stdout: '分享面板已经打开了。');
    } on DeviceError catch (e) {
      return ToolOutcome.failure(e.message);
    }
  }
}

/// `where_am_i`：最近一次定位。
class WhereAmITool extends Tool {
  WhereAmITool(this.device);

  final DeviceApi device;

  @override
  String get name => 'where_am_i';

  @override
  String get description =>
      '这台手机最近一次定位的经纬度，带精度和时间。'
      '位置权限没开、或者系统里还没有定位记录时会直说，不要自己编坐标。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
        'required': <String>[],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.read;

  @override
  String summarize(Map<String, Object?> args) => '看手机在哪';

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    try {
      if (!await device.has(DevicePerm.location)) {
        return const ToolOutcome.failure(
            '定位没打开。让人去 设置 → 扩展 里把「定位」打开，那一步会向系统要一次位置权限。');
      }
      final DeviceFix? fix = await device.location();
      if (fix == null) {
        return const ToolOutcome.failure(
            '系统里还没有最近一次定位。开一下地图或者等一下 GPS 再问。');
      }
      return ToolOutcome.success(stdout: fix.render(DateTime.now()));
    } on DeviceError catch (e) {
      return ToolOutcome.failure(e.message);
    }
  }
}

/// `find_contact`：按名字找号码。
class FindContactTool extends Tool {
  FindContactTool(this.device);

  final DeviceApi device;

  @override
  String get name => 'find_contact';

  @override
  String get description =>
      '在通讯录里按名字找号码。query 写一部分名字就行，空着就列前面几条。'
      '找到的号码只用来告诉用户或者发短信，不要往别处带。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'query': <String, Object?>{'type': 'string', 'description': '名字的一部分'},
          'limit': <String, Object?>{'type': 'integer', 'description': '最多几条，默认 10'},
        },
        'required': <String>[],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.read;

  @override
  String summarize(Map<String, Object?> args) {
    final String q = readString(args, 'query').trim();
    return q.isEmpty ? '看通讯录' : '在通讯录里找「$q」';
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String query = readString(args, 'query').trim();
    final int limit = readInt(args, 'limit', fallback: 10).clamp(1, 50).toInt();
    try {
      if (!await device.has(DevicePerm.contacts)) {
        return const ToolOutcome.failure(
            '通讯录没打开。让人去 设置 → 扩展 里把「联系人」打开，那一步会向系统要一次权限。');
      }
      final List<DeviceContact> found =
          await device.contacts(query: query, limit: limit);
      if (found.isEmpty) {
        return ToolOutcome.success(
            stdout: query.isEmpty ? '通讯录里没有带号码的联系人。' : '没有名字里有「$query」的联系人。');
      }
      return ToolOutcome.success(
        stdout: found.map((DeviceContact c) => c.line).join('\n'),
      );
    } on DeviceError catch (e) {
      return ToolOutcome.failure(e.message);
    }
  }
}

/// `sms_send`：发一条短信。
class SmsSendTool extends Tool {
  SmsSendTool(this.device);

  final DeviceApi device;

  @override
  String get name => 'sms_send';

  @override
  String get description =>
      '给一个号码发一条短信。号码和内容都自己写清，收件人别从别的地方猜。'
      '短信是在用户的号上真发出去的，发之前说清楚发给谁、说了什么。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'to': <String, Object?>{'type': 'string', 'description': '收件人号码'},
          'text': <String, Object?>{'type': 'string', 'description': '短信内容'},
        },
        'required': <String>['to', 'text'],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.write;

  @override
  String summarize(Map<String, Object?> args) =>
      '发给 ${readString(args, 'to')}：${_short(readString(args, 'text'))}';

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String to = readString(args, 'to').trim();
    final String text = readString(args, 'text');
    if (to.isEmpty) return const ToolOutcome.failure('收件人号码是空的。');
    if (text.trim().isEmpty) return const ToolOutcome.failure('短信内容是空的。');
    if (!RegExp(r'^\+?[0-9][0-9\s()-]{3,24}$').hasMatch(to)) {
      return ToolOutcome.failure('这个号码看着不像号码：$to');
    }
    try {
      if (!await device.has(DevicePerm.sms)) {
        return const ToolOutcome.failure(
            '发短信没打开。让人去 设置 → 扩展 里把「短信」打开，那一步会向系统要一次权限。');
      }
      await device.sendSms(to, text);
      return ToolOutcome.success(stdout: '发出去了，发给 $to。');
    } on DeviceError catch (e) {
      return ToolOutcome.failure(e.message);
    }
  }
}
