import 'package:flutter_test/flutter_test.dart';

import 'package:carbide_shell/core/usage.dart';

void main() {
  final DateTime now = DateTime(2026, 10, 26, 15, 30);
  final List<UsageEntry> entries = <UsageEntry>[
    UsageEntry(
        at: DateTime(2026, 10, 26, 9),
        model: 'deepseek-chat',
        prompt: 1200,
        completion: 300,
        cached: 600),
    UsageEntry(
        at: DateTime(2026, 10, 26, 11),
        model: 'deepseek-chat',
        prompt: 800,
        completion: 200),
    UsageEntry(
        at: DateTime(2026, 10, 20, 8), model: 'gpt-4o', prompt: 500, completion: 100, cached: 250),
    UsageEntry(at: DateTime(2026, 9, 1, 8), model: 'gpt-4o', prompt: 900, completion: 100),
  ];

  group('窗口', () {
    test('今天只算今天的', () {
      final UsageTotals today = UsageTotals()
        ..addAll(usageSince(entries, usageFrom(1, now)));
      expect(today.turns, 2);
      expect(today.prompt, 2000);
      expect(today.completion, 500);
      expect(today.total, 2500);
    });

    test('7 天含今天', () {
      final UsageTotals week = UsageTotals()
        ..addAll(usageSince(entries, usageFrom(7, now)));
      expect(week.turns, 3);
      expect(usageFrom(7, now), DateTime(2026, 10, 20));
    });

    test('命中率只在报了缓存时才有数', () {
      final UsageTotals today = UsageTotals()
        ..addAll(usageSince(entries, usageFrom(1, now)));
      expect(today.cacheRate, closeTo(0.3, 1e-9));
      expect(usageRate(today.cacheRate, cached: today.cached), '30%');
      expect(usageRate(0, cached: 0), '—');
    });
  });

  group('写法', () {
    test('token 数按大小换单位', () {
      expect(usageText(980), '980');
      expect(usageText(2500), '2.5k');
      expect(usageText(12400), '12k');
      expect(usageText(1030000), '1.03m');
    });
  });

  group('合计', () {
    test('按模型分组，花得多的在前', () {
      final List<UsageModelRow> models = usageByModel(entries);
      expect(models.length, 2);
      expect(models.first.model, 'deepseek-chat');
      expect(models.first.totals.total, 2500);
      expect(models.last.model, 'gpt-4o');
      expect(models.last.totals.total, 1600);
    });

    test('没填模型的算未命名', () {
      final List<UsageModelRow> models =
          usageByModel(<UsageEntry>[UsageEntry(at: now, model: '', prompt: 10)]);
      expect(models.single.model, '未命名模型');
    });

    test('最近 14 天从早到晚，缺的天补零', () {
      final List<UsageDayRow> days = usageLastDays(entries, 14, now);
      expect(days.length, 14);
      expect(days.first.day, '2026-10-13');
      expect(days.first.totals.total, 0);
      expect(days.last.day, '2026-10-26');
      expect(days.last.totals.total, 2500);
    });
  });

  test('存盘再读回来还是那一笔', () {
    final UsageEntry back = UsageEntry.fromJson(entries.first.toJson());
    expect(back.model, 'deepseek-chat');
    expect(back.prompt, 1200);
    expect(back.completion, 300);
    expect(back.cached, 600);
    expect(back.total, 1500);
    expect(back.day, '2026-10-26');
  });
}
