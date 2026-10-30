import '../core/models.dart';
import '../core/tools.dart';
import '../data/device.dart';

/// 手机上的另外几件事：打开应用、设闹钟和计时器、调音量。
///
/// 都在用户自己打开的那几项扩展里，关着就不进模型的清单。
/// 做不成的就如实说一句这台手机上做不了，不假装做过。

/// `open_app`：按名字打开一个应用。
class OpenAppTool extends Tool {
  OpenAppTool(this.device);

  final DeviceApi device;

  @override
  String get name => 'open_app';

  @override
  String get description =>
      '打开这台手机上的一个应用：给名字或者包名，比如「微信」「com.tencent.mm」。'
      '名字对不上时会回几个像的名字，那一次就不打开。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'query': <String, Object?>{
            'type': 'string',
            'description': '应用的名字或包名',
          },
        },
        'required': <String>['query'],
      };

  /// 在别人手机上点开一个应用，算写。
  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.write;

  @override
  String summarize(Map<String, Object?> args) => '打开 ${readString(args, 'query').trim()}';

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String query = readString(args, 'query').trim();
    if (query.isEmpty) return const ToolOutcome.failure('没说打开哪个应用。');
    try {
      final OpenAppResult r = await device.openApp(query);
      if (r.ok) return ToolOutcome.success(stdout: '打开了 ${r.app}。');
      final String near = r.near.isEmpty ? '' : '\n像的有：${r.near.join('、')}';
      return ToolOutcome.failure('没打开 ${r.why.isEmpty ? query : r.why}。$near'.trimRight());
    } on DeviceError catch (e) {
      return ToolOutcome.failure(e.message);
    }
  }
}

/// `set_alarm`：设一个闹钟。
class SetAlarmTool extends Tool {
  SetAlarmTool(this.device);

  final DeviceApi device;

  @override
  String get name => 'set_alarm';

  @override
  String get description =>
      '在这台手机上设一个闹钟，24 小时制。默认不出系统那一页，设完就完。'
      '要的是「几点叫我」，不是从现在起多久。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'hour': <String, Object?>{'type': 'integer', 'description': '0 到 23'},
          'minute': <String, Object?>{'type': 'integer', 'description': '0 到 59，默认 0'},
          'label': <String, Object?>{'type': 'string', 'description': '闹钟上写的一句话'},
          'show_ui': <String, Object?>{
            'type': 'boolean',
            'description': 'true 时出系统那一页，让用户自己按一下，默认 false',
          },
        },
        'required': <String>['hour'],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.write;

  @override
  String summarize(Map<String, Object?> args) {
    final int hour = readInt(args, 'hour', fallback: 7);
    final int minute = readInt(args, 'minute', fallback: 0);
    final String label = readString(args, 'label').trim();
    return '设闹钟 ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}'
        '${label.isEmpty ? '' : '（$label）'}';
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    if (!args.containsKey('hour')) return const ToolOutcome.failure('没说几点。');
    final int hour = readInt(args, 'hour', fallback: 7).clamp(0, 23).toInt();
    final int minute = readInt(args, 'minute', fallback: 0).clamp(0, 59).toInt();
    final bool showUi = args['show_ui'] == true;
    try {
      final bool ok = await device.setAlarm(
        hour: hour,
        minute: minute,
        label: readString(args, 'label').trim(),
        skipUi: !showUi,
      );
      if (!ok) return const ToolOutcome.failure('这台手机上没有闹钟能接。');
      final String when = '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      return ToolOutcome.success(
          stdout: showUi ? '闹钟填好了 $when，等用户在系统那一页按确认。' : '闹钟设好了 $when。');
    } on DeviceError catch (e) {
      return ToolOutcome.failure(e.message);
    }
  }
}

/// `set_timer`：设一个计时器。
class SetTimerTool extends Tool {
  SetTimerTool(this.device);

  final DeviceApi device;

  @override
  String get name => 'set_timer';

  @override
  String get description =>
      '设一个计时器：从现在起多少分钟（或者多少秒）之后响。默认不出系统那一页。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'minutes': <String, Object?>{'type': 'integer', 'description': '多少分钟'},
          'seconds': <String, Object?>{
            'type': 'integer',
            'description': '多少秒。和 minutes 二选一，两个都给就相加',
          },
          'label': <String, Object?>{'type': 'string', 'description': '计时器上写的一句话'},
          'show_ui': <String, Object?>{
            'type': 'boolean',
            'description': 'true 时出系统那一页，默认 false',
          },
        },
        'required': <String>[],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.write;

  @override
  String summarize(Map<String, Object?> args) {
    final int total = readInt(args, 'seconds', fallback: 0) +
        readInt(args, 'minutes', fallback: 0) * 60;
    return '设计时器 ${_span(total)}';
  }

  static String _span(int seconds) {
    if (seconds < 60) return '$seconds 秒';
    final int m = seconds ~/ 60;
    final int s = seconds % 60;
    return s == 0 ? '$m 分钟' : '$m 分 $s 秒';
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final int total = readInt(args, 'seconds', fallback: 0) +
        readInt(args, 'minutes', fallback: 0) * 60;
    if (total < 1) return const ToolOutcome.failure('没说多久之后响。');
    final bool showUi = args['show_ui'] == true;
    try {
      final bool ok = await device.setTimer(
        seconds: total,
        label: readString(args, 'label').trim(),
        skipUi: !showUi,
      );
      if (!ok) return const ToolOutcome.failure('这台手机上没有计时器能接。');
      return ToolOutcome.success(
          stdout: showUi ? '计时器填好了 ${_span(total)}，等用户按确认。' : '计时器设好了 ${_span(total)}。');
    } on DeviceError catch (e) {
      return ToolOutcome.failure(e.message);
    }
  }
}

/// `volume`：看和调音量、铃声方式。不带参数就是看一眼。
class VolumeTool extends Tool {
  VolumeTool(this.device);

  final DeviceApi device;

  @override
  String get name => 'volume';

  @override
  String get description =>
      '看或者改这台手机的音量：媒体、铃声、闹钟、通知，还有铃声方式（正常、振动、静音）。'
      '什么参数都不给就是看一眼。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'stream': <String, Object?>{
            'type': 'string',
            'enum': <String>['music', 'ring', 'alarm', 'notification'],
            'description': '改哪一档，不给就只读',
          },
          'percent': <String, Object?>{
            'type': 'integer',
            'description': '这一档改到百分之多少，0 到 100',
          },
          'mode': <String, Object?>{
            'type': 'string',
            'enum': <String>['normal', 'vibrate', 'silent'],
            'description': '铃声方式：正常 / 振动 / 静音',
          },
        },
        'required': <String>[],
      };

  /// 只读是看一眼，带 stream / mode 就是改。
  @override
  ToolRisk classify(Map<String, Object?> args) =>
      readString(args, 'stream').isEmpty && readString(args, 'mode').isEmpty
          ? ToolRisk.read
          : ToolRisk.write;

  @override
  String summarize(Map<String, Object?> args) {
    final String stream = readString(args, 'stream').trim();
    final String mode = readString(args, 'mode').trim();
    if (stream.isEmpty && mode.isEmpty) return '看现在的音量';
    final List<String> parts = <String>[];
    if (stream.isNotEmpty) parts.add('$stream ${readInt(args, 'percent', fallback: 0)}%');
    if (mode.isNotEmpty) parts.add('铃声方式 $mode');
    return '调音量：${parts.join('、')}';
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String stream = readString(args, 'stream').trim();
    final String mode = readString(args, 'mode').trim();
    final bool change = stream.isNotEmpty || mode.isNotEmpty;
    try {
      final DeviceVolume now = change
          ? await device.setVolume(
              stream: stream,
              percent: stream.isEmpty ? -1 : readInt(args, 'percent', fallback: -1),
              mode: mode,
            )
          : await device.volume();
      if (!now.ok) {
        return ToolOutcome.failure(now.why.isEmpty ? '这台手机上读不到音量。' : now.why);
      }
      return ToolOutcome.success(stdout: '${change ? '改好了，现在' : '现在'}：\n${now.line}');
    } on DeviceError catch (e) {
      return ToolOutcome.failure(e.message);
    }
  }
}
