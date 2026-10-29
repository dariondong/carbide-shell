/// DeepSeek 的峰谷时段。
///
/// 规则按官方定价页：北京时间周一至周五（不含法定节假日）9:00–12:00、14:00–18:00 是高峰，
/// 其余时间全按谷时算 —— 工作日的非高峰、周六周日全天、法定节假日全天都算谷时；
/// 调休上班的周末也算谷时。谷时的价格是高峰的一半。
///
/// 节假日和调休的名单放在设置里可以改：官方每年公布一次，内置的那张表只是起点。
library;

/// 内置的法定节假日（北京时间的日期，`2025-01-01` 这样写）。
///
/// 官方每年公布一次排期：内置表只放了已经公布的那一年，新的排期在设置 → 对话 →
/// 峰谷时段里按行填进去，不用等一个版本。
const Set<String> kCnHolidays2025 = <String>{
  '2025-01-01',
  // 春节
  '2025-01-28', '2025-01-29', '2025-01-30', '2025-01-31',
  '2025-02-01', '2025-02-02', '2025-02-03', '2025-02-04',
  // 清明
  '2025-04-04', '2025-04-05', '2025-04-06',
  // 劳动节
  '2025-05-01', '2025-05-02', '2025-05-03', '2025-05-04', '2025-05-05',
  // 端午
  '2025-05-31', '2025-06-01', '2025-06-02',
  // 国庆与中秋
  '2025-10-01', '2025-10-02', '2025-10-03', '2025-10-04',
  '2025-10-05', '2025-10-06', '2025-10-07', '2025-10-08',
};

/// 2025 年调休上班的那几个周末。按规则它们仍然算谷时，列在这里只为在界面上说清楚。
const Set<String> kCnMakeup2025 = <String>{
  '2025-01-26', '2025-02-08', '2025-04-27', '2025-09-28', '2025-10-11',
};

/// `2026-10-29`：北京时间的日期。
String bjDayKey(DateTime at) {
  final DateTime bj = at.toUtc().add(const Duration(hours: 8));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${bj.year}-${two(bj.month)}-${two(bj.day)}';
}

/// 北京时间的时刻，`09:30`。
String bjClockText(DateTime at) {
  final DateTime bj = at.toUtc().add(const Duration(hours: 8));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(bj.hour)}:${two(bj.minute)}';
}

/// 北京时间这一天是星期几，1 = 周一。
int bjWeekday(DateTime at) {
  final DateTime bj = at.toUtc().add(const Duration(hours: 8));
  return bj.weekday;
}

/// 现在是高峰还是谷时，还有多久换段。
class PeakState {
  const PeakState({
    required this.peak,
    required this.holiday,
    required this.makeup,
    required this.weekend,
    this.nextChange,
  });

  /// true = 高峰，按标准价；false = 谷时，价格减半。
  final bool peak;

  /// 这一天是法定节假日。
  final bool holiday;

  /// 这一天是调休上班的周末（仍然按谷时算）。
  final bool makeup;

  final bool weekend;

  /// 下一次换段的时刻（本地时间）。整天都是谷时的时候是 null。
  final DateTime? nextChange;

  String get label => peak ? '高峰' : '谷时';

  /// 一句话说清现在什么价。
  String get sentence {
    if (peak) {
      return '当前为 DeepSeek 高峰时段（工作日 9:00–12:00、14:00–18:00），按标准价格计费。'
          '建议精简上下文，非紧急任务可安排在谷时执行。';
    }
    if (makeup) return '今天是调休上班日，但 DeepSeek 仍按谷时计价，可正常安排任务。';
    if (holiday) return '今天是法定节假日，DeepSeek 全天按谷时计价，适合安排批量任务。';
    if (weekend) return '今天是周末，DeepSeek 全天按谷时计价，适合安排批量任务。';
    return '当前为 DeepSeek 谷时时段，调用价格为高峰时段的一半，适合批量处理、长文本、非紧急任务。';
  }

  /// 离换段还有多久，一句话。换段在一天以后就不说了。
  String? get hint {
    final DateTime? next = nextChange;
    if (next == null) return null;
    final Duration left = next.difference(DateTime.now());
    if (left.isNegative) return null;
    final int minutes = left.inMinutes;
    if (minutes > 240) return null;
    if (peak) {
      return '距离谷时开始还有 $minutes 分钟，非紧急任务可稍后执行，费用减半。';
    }
    return '距离进入高峰时段还有 $minutes 分钟，批量任务建议尽快安排或改到谷时执行。';
  }
}

/// 一个装好节假日的时钟。时区固定按北京时间算，设备在哪都一样。
class DeepSeekClock {
  const DeepSeekClock({
    this.holidays = kCnHolidays2025,
    this.makeupDays = kCnMakeup2025,
  });

  /// 内置表 + 用户在设置里补的那几天。读不懂的写法直接丢掉。
  factory DeepSeekClock.withExtra({
    Iterable<String> extraHolidays = const <String>[],
    Iterable<String> extraMakeup = const <String>[],
  }) =>
      DeepSeekClock(
        holidays: <String>{...kCnHolidays2025, ..._dates(extraHolidays)},
        makeupDays: <String>{...kCnMakeup2025, ..._dates(extraMakeup)},
      );

  /// 只认 `2026-10-01` 这种写法，其他一律不要。
  static Iterable<String> _dates(Iterable<String> raw) {
    final List<String> out = <String>[];
    for (final String line in raw) {
      final String one = line.trim();
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(one)) out.add(one);
    }
    return out;
  }

  final Set<String> holidays;
  final Set<String> makeupDays;

  bool isHoliday(DateTime at) => holidays.contains(bjDayKey(at));

  bool isMakeup(DateTime at) => makeupDays.contains(bjDayKey(at));

  /// 北京时间这一天，9:00–12:00 或 14:00–18:00。
  bool isPeakHour(DateTime at) {
    final DateTime bj = at.toUtc().add(const Duration(hours: 8));
    final int m = bj.hour * 60 + bj.minute;
    return (m >= 9 * 60 && m < 12 * 60) || (m >= 14 * 60 && m < 18 * 60);
  }

  PeakState state(DateTime at) {
    final int wd = bjWeekday(at);
    final bool weekend = wd >= 6;
    final bool holiday = isHoliday(at);
    final bool makeup = isMakeup(at);
    // 周末和节假日一律全天谷时；调休上班的周末也一样。
    final bool workday = !weekend && !holiday;
    final bool peak = workday && isPeakHour(at);
    DateTime? next;
    if (workday) {
      final DateTime bj = at.toUtc().add(const Duration(hours: 8));
      final int m = bj.hour * 60 + bj.minute;
      int target = -1;
      if (peak) {
        target = (m >= 9 * 60 && m < 12 * 60) ? 12 * 60 : 18 * 60;
      } else if (m < 9 * 60) {
        target = 9 * 60;
      } else if (m >= 12 * 60 && m < 14 * 60) {
        target = 14 * 60;
      }
      if (target >= 0) {
        // 北京时间的墙上时刻换成真正的瞬间：UTC = 墙上时刻 - 8 小时。
        next = DateTime.utc(bj.year, bj.month, bj.day, target ~/ 60, target % 60)
            .subtract(const Duration(hours: 8));
      }
    }
    return PeakState(
      peak: peak,
      holiday: holiday,
      makeup: makeup,
      weekend: weekend,
      nextChange: next,
    );
  }
}

/// 这个模型名算不算 DeepSeek 那一支。
bool isDeepSeekModel(String model) {
  final String m = model.toLowerCase();
  return m.contains('deepseek');
}
