import 'package:carbide_shell/core/deepseek.dart';
import 'package:carbide_shell/core/pricing.dart';
import 'package:carbide_shell/core/usage.dart';
import 'package:flutter_test/flutter_test.dart';

/// 北京时间 -> 真实瞬间。
DateTime bj(int y, int m, int d, int h, [int min = 0]) =>
    DateTime.utc(y, m, d, h, min).subtract(const Duration(hours: 8));

void main() {
  const DeepSeekClock clock = DeepSeekClock();

  group('峰谷时段', () {
    test('工作日 9-12、14-18 是高峰', () {
      expect(clock.state(bj(2026, 10, 28, 9)).peak, isTrue); // 周三
      expect(clock.state(bj(2026, 10, 28, 11, 59)).peak, isTrue);
      expect(clock.state(bj(2026, 10, 28, 12)).peak, isFalse);
      expect(clock.state(bj(2026, 10, 28, 13, 59)).peak, isFalse);
      expect(clock.state(bj(2026, 10, 28, 14)).peak, isTrue);
      expect(clock.state(bj(2026, 10, 28, 17, 59)).peak, isTrue);
      expect(clock.state(bj(2026, 10, 28, 18)).peak, isFalse);
      expect(clock.state(bj(2026, 10, 28, 8, 30)).peak, isFalse);
    });

    test('周末、节假日、调休上班日全天谷时', () {
      final PeakState sat = clock.state(bj(2026, 10, 31, 10));
      expect(sat.peak, isFalse);
      expect(sat.weekend, isTrue);
      final PeakState holiday = clock.state(bj(2025, 10, 1, 10));
      expect(holiday.peak, isFalse);
      expect(holiday.holiday, isTrue);
      expect(holiday.sentence, contains('法定节假日'));
      final PeakState makeup = clock.state(bj(2025, 10, 11, 10));
      expect(makeup.peak, isFalse);
      expect(makeup.makeup, isTrue);
      expect(makeup.sentence, contains('调休'));
      // 调休的周末按谷时，工作日的高峰句子里不该出现周末那句。
      expect(clock.state(bj(2026, 10, 28, 10)).sentence, contains('高峰时段'));
    });

    test('临近换段能算出还有几分钟', () {
      final PeakState before = clock.state(bj(2026, 10, 28, 8, 40));
      expect(before.nextChange, isNotNull);
      expect(before.nextChange!.difference(bj(2026, 10, 28, 8, 40)).inMinutes, 20);
      final PeakState inPeak = clock.state(bj(2026, 10, 28, 11, 30));
      expect(inPeak.nextChange!.difference(bj(2026, 10, 28, 11, 30)).inMinutes, 30);
      expect(clock.state(bj(2026, 10, 31, 10)).nextChange, isNull);
    });

    test('北京时间的写法与模型名', () {
      expect(bjClockText(bj(2026, 10, 28, 9, 5)), '09:05');
      expect(bjDayKey(bj(2026, 10, 28, 23, 30)), '2026-10-28');
      expect(isDeepSeekModel('deepseek-chat'), isTrue);
      expect(isDeepSeekModel('gpt-4o'), isFalse);
    });
  });

  group('计价', () {
    const ModelPrice price = ModelPrice(input: 2, cache: 0.5, output: 8);

    test('输入、缓存、输出分开算', () {
      final CostSplit split =
          costSplitOf(prompt: 1000000, completion: 100000, cached: 400000, price: price);
      expect(split.promptTotal, closeTo(1.4, 1e-9));
      expect(split.output, closeTo(0.8, 1e-9));
      expect(split.total, closeTo(2.2, 1e-9));
    });

    test('谷时按一半', () {
      expect(
        costOf(prompt: 1000000, completion: 100000, cached: 400000, price: price, factor: 0.5),
        closeTo(1.1, 1e-9),
      );
      expect(peakFactor(peakValley: true, at: bj(2026, 10, 28, 12)), 0.5);
      expect(peakFactor(peakValley: true, at: bj(2026, 10, 28, 10)), 1);
      expect(peakFactor(peakValley: false, at: bj(2026, 10, 28, 12)), 1);
    });

    test('手填的价盖住内置表，读坏的回落', () {
      final PriceQuote manual = quotePrice(
          manual: <String, Object?>{'input': 1, 'output': 2}, model: 'deepseek-chat');
      expect(manual.source, PriceSource.manual);
      expect(manual.price!.input, 1);
      expect(manual.peakValley, isTrue);

      final PriceQuote builtin = quotePrice(manual: <String, Object?>{}, model: 'deepseek-chat');
      expect(builtin.source, PriceSource.builtin);
      expect(builtin.price!.output, 8);

      final PriceQuote unknown = quotePrice(manual: <String, Object?>{}, model: 'unknown-x');
      expect(unknown.known, isFalse);

      final PriceQuote broken =
          quotePrice(manual: <String, Object?>{'input': 'x'}, model: 'deepseek-chat');
      expect(broken.source, PriceSource.builtin);
    });

    test('钱的写法', () {
      expect(moneyText(0), '¥0');
      expect(moneyText(0.00123), '¥0.0012');
      expect(moneyText(0.1234), '¥0.123');
      expect(moneyText(12.345), '¥12.35');
    });

    test('账本把输入、输出费用分开累计', () {
      final UsageTotals totals = UsageTotals()
        ..add(UsageEntry(at: DateTime(2026, 10, 28), model: 'm', prompt: 10, completion: 5, costIn: 0.02, costOut: 0.03))
        ..add(UsageEntry(at: DateTime(2026, 10, 29), model: 'm', prompt: 10, completion: 5, costIn: 0.01, costOut: 0.01));
      expect(totals.costIn, closeTo(0.03, 1e-9));
      expect(totals.costOut, closeTo(0.04, 1e-9));
      expect(totals.cost, closeTo(0.07, 1e-9));

      final UsageEntry back = UsageEntry.fromJson(<String, Object?>{
        'at': '2026-10-28T10:00:00.000',
        'model': 'm',
        'prompt': 10,
        'completion': 5,
        'costIn': 0.02,
        'costOut': 0.03,
      });
      expect(back.costIn, closeTo(0.02, 1e-9));
      expect(back.cost, closeTo(0.05, 1e-9));
    });
  });
}
