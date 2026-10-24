import 'package:carbide_shell/core/markdown.dart';
import 'package:flutter_test/flutter_test.dart';

/// 把块压成「种类:内容」的短串，读起来跟期望值好对。
String _show(List<MdBlock> blocks) => blocks
    .map((MdBlock b) => '${b.kind.name}'
        '${b.kind == MdBlockKind.heading ? '/${b.level}' : ''}'
        '${b.kind == MdBlockKind.bullet ? '/${b.level}' : ''}'
        '${b.kind == MdBlockKind.ordered ? '/${b.level}#${b.number}' : ''}'
        '${b.kind == MdBlockKind.code ? '/${b.lang}' : ''}'
        ':${b.kind == MdBlockKind.table ? b.rows.toString() : b.text}')
    .join(' | ');

String _inline(List<MdSpan> spans) =>
    spans.map((MdSpan s) => '${s.kind.name}${s.href.isEmpty ? '' : '@${s.href}'}:${s.text}').join(' | ');

void main() {
  test('标题与段落', () {
    expect(_show(parseMarkdown('## 结论\n磁盘还行。')), 'heading/2:结论 | paragraph:磁盘还行。');
  });

  test('井号后面没空格不算标题', () {
    expect(_show(parseMarkdown('###### 小标题\n#没空格')),
        'heading/6:小标题 | paragraph:#没空格');
  });

  test('围栏代码连语言名', () {
    expect(
      _show(parseMarkdown('看这个：\n```bash\nls -l /tmp\ndf -h\n```\n好了。')),
      'paragraph:看这个： | code/bash:ls -l /tmp\ndf -h | paragraph:好了。',
    );
  });

  test('围栏没写完时（正在逐字输出）剩下的都算代码', () {
    expect(_show(parseMarkdown('```\nsudo systemctl status nginx')),
        'code/:sudo systemctl status nginx');
  });

  test('波浪号围栏也认', () {
    expect(_show(parseMarkdown('~~~json\n{}\n~~~')), 'code/json:{}');
  });

  test('无序列表，缩进算第二层', () {
    expect(_show(parseMarkdown('- 磁盘\n- 内存\n  - swap\n- 服务')),
        'bullet/1:磁盘 | bullet/1:内存 | bullet/2:swap | bullet/1:服务');
  });

  test('有序列表留原文的号', () {
    expect(_show(parseMarkdown('3. 第三步\n4. 第四步')),
        'ordered/1#3:第三步 | ordered/1#4:第四步');
  });

  test('列表项换行续写算同一项', () {
    expect(_show(parseMarkdown('- 先看磁盘\n  再看内存')), 'bullet/1:先看磁盘\n再看内存');
  });

  test('引用连成一段', () {
    expect(_show(parseMarkdown('> 一句\n> 又一句')), 'quote:一句\n又一句');
  });

  test('分隔线', () {
    expect(_show(parseMarkdown('上\n\n---\n\n下')), 'paragraph:上 | rule: | paragraph:下');
  });

  test('表格', () {
    expect(
      _show(parseMarkdown('| 项 | 值 |\n| --- | --- |\n| 磁盘 | 舒服 |\n| 内存 | 紧 |')),
      'table:[[项, 值], [磁盘, 舒服], [内存, 紧]]',
    );
  });

  test('段落里的换行留着', () {
    expect(_show(parseMarkdown('第一行\n第二行\n\n另起一段')),
        'paragraph:第一行\n第二行 | paragraph:另起一段');
  });

  test('列表后面的段落不会被吃进列表', () {
    expect(_show(parseMarkdown('- 一条\n\n说完接着写')), 'bullet/1:一条 | paragraph:说完接着写');
  });

  test('行内的粗体、代码、斜体与链接', () {
    expect(
      _inline(parseInline('看 **这个** 和 `那个` 还有 *斜* 以及 [链接](https://x.y)')),
      'plain:看  | bold:这个 | plain: 和  | code:那个 | plain: 还有  | '
      'italic:斜 | plain: 以及  | link@https://x.y:链接',
    );
  });

  test('星号没写完就当普通字', () {
    expect(_inline(parseInline('**没写完')), 'plain:**没写完');
  });

  test('词里的下划线不算斜体', () {
    expect(_inline(parseInline('foo_bar_baz')), 'plain:foo_bar_baz');
  });

  test('删除线与下划线粗体', () {
    expect(_inline(parseInline('~~不要~~ __重__')), 'strike:不要 | plain:  | bold:重');
  });

  test('行内代码里的星号不当作粗体', () {
    expect(_inline(parseInline('`a * b * c`')), 'code:a * b * c');
  });
}
