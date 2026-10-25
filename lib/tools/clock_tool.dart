import '../core/models.dart';
import '../core/tools.dart';

/// `clock`：读这台设备现在的日期、时刻和时区。
///
/// 时刻不进系统提示词。那一行在最前面，每过一分钟就变一个字，
/// 整段前缀的缓存每次都作废，模型那边按新内容重新算一遍，花的是全额。
class ClockTool extends Tool {
  @override
  String get name => 'clock';

  @override
  String get description => '读这台设备现在的日期、时刻和时区。排一次性时间、算还有多久的时候用，不要自己猜。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.read;

  @override
  String summarize(Map<String, Object?> args) => '看现在几点';

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final DateTime now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    const List<String> week = <String>['一', '二', '三', '四', '五', '六', '日'];
    final Duration off = now.timeZoneOffset;
    final String sign = off.isNegative ? '-' : '+';
    final Duration abs = off.abs();
    return ToolOutcome.success(
      stdout: '${now.year}-${two(now.month)}-${two(now.day)} '
          '${two(now.hour)}:${two(now.minute)}:${two(now.second)}，'
          '星期${week[now.weekday - 1]}，UTC$sign${two(abs.inHours)}:${two(abs.inMinutes % 60)}（设备本地时间）。',
    );
  }
}
