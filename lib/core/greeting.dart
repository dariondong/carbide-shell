/// 对话页右侧那几行问候语。
///
/// 按北京时间分时段选一句，用 DeepSeek 的时候再附加一句峰谷时段与建议。
/// 文案是固定的一小撮，不花 token 去生成。
library;

import 'deepseek.dart';

/// 现在这个钟点该说哪一句。
String greetingAt(DateTime at) {
  final int h = at.toUtc().add(const Duration(hours: 8)).hour;
  if (h >= 5 && h < 9) return '早上好，新的一天从清晰的思路开始。';
  if (h >= 9 && h < 12) return '上午好，需要我帮你梳理什么？';
  if (h >= 12 && h < 14) return '中午好，记得稍作休息。';
  if (h >= 14 && h < 18) return '下午好，继续推进今天的任务吧。';
  if (h >= 18 && h < 23) return '晚上好，今天辛苦了。';
  return '夜深了，注意休息，重要任务可以明天继续。';
}

/// 一行问候加一行（可选的）峰谷提示。
class Greeting {
  const Greeting({required this.line, this.hint = '', this.peak, this.peakLine = ''});

  final String line;

  /// 峰谷那一段，像「距离进入高峰时段还有 20 分钟…」。
  final String hint;

  /// 现在是不是高峰。没用 DeepSeek 时是 null。
  final bool? peak;

  /// 一句总论，像「当前 DeepSeek 为谷时计价，适合处理批量任务。」
  final String peakLine;

  bool get hasPeak => peak != null;
}

/// 拼出这一刻该显示的那几句。
///
/// [model] 是这场对话正在用的模型名，只有 DeepSeek 那一支才带峰谷提示。
Greeting greetingFor({
  required DateTime at,
  required String model,
  bool peakHint = true,
  DeepSeekClock clock = const DeepSeekClock(),
}) {
  final String line = greetingAt(at);
  if (!peakHint || !isDeepSeekModel(model)) {
    return Greeting(line: line);
  }
  final PeakState state = clock.state(at);
  final String peakLine = state.peak
      ? '当前 DeepSeek 为高峰时段，按标准价格计费。'
      : '当前 DeepSeek 为 ${state.holiday ? '节假日谷时' : (state.weekend ? '周末谷时' : '谷时')} 计价，费用减半。';
  final String? near = state.hint;
  return Greeting(
    line: line,
    hint: near ?? state.sentence,
    peak: state.peak,
    peakLine: peakLine,
  );
}
