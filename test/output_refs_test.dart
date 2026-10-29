import 'package:carbide_shell/core/output_refs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('认得字里写到的图和网页', () {
    const String text = '报告写好了：reports/disk.html，图在 reports/disk.png。';
    final List<String> refs = outputRefs(text);
    expect(refs, contains('reports/disk.html'));
    expect(refs, contains('reports/disk.png'));
  });

  test('外链、代码里的路径都不算', () {
    const String text =
        '看 https://example.com/a.png 和 data:image/png;base64,AAA 以及 http://x.test/b.html';
    expect(outputRefs(text), isEmpty);
  });

  test('开头的 ./ 去掉，重复的只留一条', () {
    final List<String> refs = outputRefs('./reports/a.png 和 reports/a.png');
    expect(refs, <String>['reports/a.png']);
  });

  test('别的后缀不挂预览', () {
    expect(outputRefs('logs/app.log 和 notes.txt'), isEmpty);
  });

  test('后缀决定是图还是网页', () {
    expect(isImageRef('a/b.png'), isTrue);
    expect(isImageRef('a/b.html'), isFalse);
    expect(isImageRef('a/b.HTM'), isFalse);
  });
}
