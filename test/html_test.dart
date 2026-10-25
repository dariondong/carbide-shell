import 'package:carbide_shell/core/html.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('标题、段落、粗细斜都收成 markdown', () {
    final String md = htmlToMarkdown(
      '<h2>周报</h2><p>这周把 <b>上传</b> 和 <i>下载</i> 做完了。</p>',
    );
    expect(md, contains('## 周报'));
    expect(md, contains('**上传**'));
    expect(md, contains('*下载*'));
    expect(md.split('\n\n').length, 2);
  });

  test('列表缩进按层走，有序表自己数', () {
    final String md = htmlToMarkdown(
      '<ul><li>一<ul><li>一之一</li></ul></li><li>二</li></ul>'
      '<ol><li>甲</li><li>乙</li></ol>',
    );
    expect(md, contains('- 一'));
    expect(md, contains('  - 一之一'));
    expect(md, contains('- 二'));
    expect(md, contains('1. 甲'));
    expect(md, contains('2. 乙'));
  });

  test('代码块里的缩进和空行原样留着', () {
    final String md = htmlToMarkdown(
      '<pre><code>void main() {\n  print(1);\n\n  print(2);\n}</code></pre>',
    );
    expect(md, startsWith('```'));
    expect(md, contains('  print(1);\n\n  print(2);'));
  });

  test('表格出一行表头、一条分隔线、一行数据', () {
    final String md = htmlToMarkdown(
      '<table><tr><th>名</th><th>数</th></tr><tr><td>A</td><td>1</td></tr></table>',
    );
    final List<String> rows = md.split('\n');
    expect(rows[0], '| 名 | 数 |');
    expect(rows[1], '| --- |');
    expect(rows[2], '| A | 1 |');
  });

  test('链接、图片、实体都认得出来', () {
    final String md = htmlToMarkdown(
      '<p><a href="https://a.b/c?x=1&amp;y=2">去</a>'
      '<img src="i.png" alt="图"><img src="j.png"> &mdash; &#25968;</p>',
    );
    expect(md, contains('[去](https://a.b/c?x=1&y=2)'));
    expect(md, contains('[图]'));
    expect(md, contains('[图片]'));
    expect(md, contains('— 数'));
  });

  test('脚本、样式、head 里面的字不出现', () {
    final String md = htmlToMarkdown(
      '<html><head><title>标题</title><style>p{color:red}</style></head>'
      '<body><p>正文</p><script>alert(1)</script></body></html>',
    );
    expect(md, '正文');
  });

  test('空输入给空串，纯文字原样', () {
    expect(htmlToMarkdown(''), '');
    expect(htmlToMarkdown('好'), '好');
  });

  test('没有 alt 的图片也留个记号，不留空标签', () {
    final String md = htmlToMarkdown('<div><img src="a.png"></div>');
    expect(md, '[图片]');
    expect(md, isNot(contains('<')));
  });
}
