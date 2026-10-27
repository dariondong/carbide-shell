import 'dart:io';

import 'package:carbide_shell/core/models.dart';
import 'package:carbide_shell/data/temp_files.dart';
import 'package:carbide_shell/tools/render_tool.dart';
import 'package:flutter_test/flutter_test.dart';

const ToolContext _ctx = ToolContext(workspace: '/tmp', desktop: true);

void main() {
  late Directory dir;
  late TempFiles files;
  late RenderCheckTool tool;

  setUp(() {
    dir = Directory(
        '${Directory.systemTemp.path}/carbide_render_${DateTime.now().microsecondsSinceEpoch}');
    files = TempFiles(dir);
    files.ensure();
    tool = RenderCheckTool(files);
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('既没路径也没 HTML 就说没东西可查', () async {
    final ToolOutcome out = await tool.run(<String, Object?>{}, _ctx);
    expect(out.ok, isFalse);
    expect(out.error, contains('path'));
  });

  test('路径不对就说读不出来', () async {
    final ToolOutcome out =
        await tool.run(<String, Object?>{'path': 'reports/none.html'}, _ctx);
    expect(out.ok, isFalse);
    expect(out.error, contains('读不出'));
  });

  test('一段干净的邮件 HTML 挑不出毛病', () async {
    const String page = '<!DOCTYPE html><html><head><meta charset="utf-8"></head>'
        '<body style="margin:0"><table role="presentation" style="width:100%">'
        '<tr style="vertical-align:top"><td style="padding:8px">hi</td>'
        '</tr></table></body></html>';
    final ToolOutcome out = await tool.run(<String, Object?>{'html': page}, _ctx);
    expect(out.ok, isTrue, reason: out.error);
    expect(out.stdout, contains('没发现'));
    expect(out.meta['warnings'], 0);
  });

  test('style 块、script、超宽、标签不配平都点出来', () async {
    const String page = '<html><head><style>p{}</style></head><body>'
        '<script>x()</script><div style="width:980px"><p>hi</body></html>';
    final ToolOutcome out = await tool.run(<String, Object?>{'html': page}, _ctx);
    expect(out.ok, isTrue, reason: out.error);
    expect(out.stdout, contains('<style>'));
    expect(out.stdout, contains('<script>'));
    expect(out.stdout, contains('640'));
    expect(out.stdout, contains('配平'));
    expect(out.meta['warnings'], greaterThan(0));
  });

  test('查临时区里的文件，标题带上路径', () async {
    await files.saveText('reports/a.html', '<html><body><p>hi</body></html>');
    final ToolOutcome out =
        await tool.run(<String, Object?>{'path': 'reports/a.html'}, _ctx);
    expect(out.ok, isTrue, reason: out.error);
    expect(out.stdout, contains('reports/a.html'));
  });

  test('说不截图，别让人以为看得到画面', () async {
    final ToolOutcome out = await tool.run(<String, Object?>{
      'html': '<html><body><p>hi</p></body></html>',
    }, _ctx);
    expect(out.stdout, contains('截图'));
  });

  test('只读，不拦', () {
    expect(tool.classify(<String, Object?>{'html': '<p>x</p>'}), ToolRisk.read);
  });
}
