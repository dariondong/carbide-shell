import 'package:carbide_shell/core/deepseek.dart';
import 'package:carbide_shell/core/greeting.dart';
import 'package:carbide_shell/core/poems.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime bj(int y, int m, int d, int h, [int min = 0]) =>
    DateTime.utc(y, m, d, h, min).subtract(const Duration(hours: 8));

void main() {
  test('古诗轮子：不连着重复，库里的都会抽到', () {
    final PoemWheel wheel = PoemWheel(seed: 7);
    String last = '';
    int repeats = 0;
    final Set<String> seen = <String>{};
    for (int i = 0; i < 400; i += 1) {
      final Poem poem = wheel.next()!;
      if (poem.line == last) repeats += 1;
      last = poem.line;
      seen.add(poem.line);
    }
    expect(repeats, 0);
    expect(seen.length, kPoems.length);
    final PoemWheel single = PoemWheel(poems: <Poem>[kPoems.first], seed: 1);
    expect(single.next()!.line, kPoems.first.line);
    expect(single.next()!.line, kPoems.first.line);
  });

  test('古诗拆行与间隔夹取', () {
    final Poem first = kPoems.first;
    expect(first.head, '长风破浪会有时');
    expect(first.tail, '直挂云帆济沧海');
    expect(first.byline, '《行路难》 李白');
    expect(clampPoemEvery(3), kPoemEveryMin);
    expect(clampPoemEvery(300), kPoemEveryMax);
    expect(clampPoemEvery(30), 30);
  });

  test('问候语按北京时间分时段', () {
    expect(greetingAt(bj(2026, 10, 28, 6)), startsWith('早上好'));
    expect(greetingAt(bj(2026, 10, 28, 10)), startsWith('上午好'));
    expect(greetingAt(bj(2026, 10, 28, 12)), startsWith('中午好'));
    expect(greetingAt(bj(2026, 10, 28, 15)), startsWith('下午好'));
    expect(greetingAt(bj(2026, 10, 28, 20)), startsWith('晚上好'));
    expect(greetingAt(bj(2026, 10, 28, 2)), startsWith('夜深了'));
  });

  test('DeepSeek 才带峰谷提示', () {
    const DeepSeekClock clock = DeepSeekClock();
    final Greeting valley =
        greetingFor(at: bj(2026, 10, 28, 12), model: 'deepseek-chat', clock: clock);
    expect(valley.hasPeak, isTrue);
    expect(valley.peak, isFalse);
    expect(valley.peakLine, contains('谷时'));

    final Greeting peak =
        greetingFor(at: bj(2026, 10, 28, 10), model: 'deepseek-chat', clock: clock);
    expect(peak.peak, isTrue);

    expect(greetingFor(at: bj(2026, 10, 28, 12), model: 'gpt-4o', clock: clock).hasPeak,
        isFalse);
    expect(
      greetingFor(
              at: bj(2026, 10, 28, 12),
              model: 'deepseek-chat',
              peakHint: false,
              clock: clock)
          .hasPeak,
      isFalse,
    );
  });
}
