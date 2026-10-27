import 'dart:io';

import 'package:carbide_shell/core/models.dart';
import 'package:carbide_shell/data/temp_files.dart';
import 'package:carbide_shell/tools/report_tool.dart';
import 'package:flutter_test/flutter_test.dart';

const ToolContext _ctx = ToolContext(workspace: '/tmp', desktop: true);

Map<String, Object?> _reportArgs({String template = 'report'}) => <String, Object?>{
      'title': 'mgr 状态摘要',
      'subtitle': 'orangepizero3 · 2026-10-27',
      'template': template,
      'metrics': <Object?>[
        <String, Object?>{'value': '41%', 'label': '磁盘', 'tone': 'warn'},
        <String, Object?>{'value': '0', 'label': '失败服务', 'tone': 'ok'},
      ],
      'sections': <Object?>[
        <String, Object?>{'level': 'P0', 'heading': 'dufs 匿名可写', 'body': '启动参数含 -A'},
        <String, Object?>{'kind': 'note', 'color': 'amber', 'heading': '更正', 'body': 'ufw 是不活动'},
      ],
      'footer': '数据来源：SSH 实时只读采集',
    };

void main() {
  late Directory dir;
  late TempFiles files;
  late ReportRenderTool tool;

  setUp(() {
    dir = Directory(
        '${Directory.systemTemp.path}/carbide_report_${DateTime.now().microsecondsSinceEpoch}');
    files = TempFiles(dir);
    files.ensure();
    tool = ReportRenderTool(files);
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('没标题就不排', () async {
    final ToolOutcome out = await tool.run(<String, Object?>{}, _ctx);
    expect(out.ok, isFalse);
    expect(out.error, contains('title'));
  });

  test('网页版落到 reports/ 下，标题当文件名', () async {
    final ToolOutcome out = await tool.run(_reportArgs(), _ctx);
    expect(out.ok, isTrue, reason: out.error);
    expect(out.stdout, contains('reports/mgr_状态摘要.html'));
    final File saved = File('${dir.path}/reports/mgr_状态摘要.html');
    expect(saved.existsSync(), isTrue);
    final String page = saved.readAsStringSync();
    expect(page.startsWith('<!DOCTYPE html>'), isTrue);
    expect(page, contains('<style>'));
    expect(page, contains('mgr 状态摘要'));
  });

  test('邮件版不带 style 块，样式全在行内', () async {
    final ToolOutcome out = await tool.run(
        _reportArgs(template: 'email')..['path'] = 'reports/mgr-邮件.html', _ctx);
    expect(out.ok, isTrue, reason: out.error);
    final String page = File('${dir.path}/reports/mgr-邮件.html').readAsStringSync();
    expect(page, isNot(contains('<style')));
    expect(page, contains('<table role="presentation"'));
    expect(page, contains('background:#C0281C')); // P0 的红标签
    expect(page, contains('border-left:3px solid #B26A00')); // note 的提示框
  });

  test('纯文本默认直接把正文回给我，也落一份 md', () async {
    final ToolOutcome out = await tool.run(_reportArgs(template: 'plain'), _ctx);
    expect(out.ok, isTrue, reason: out.error);
    expect(out.stdout, contains('# mgr 状态摘要'));
    expect(out.stdout, contains('- 磁盘：41%'));
    expect(out.stdout, contains('## [P0] dufs 匿名可写'));
    expect(out.stdout, contains('> 更正'));
    expect(File('${dir.path}/reports/mgr_状态摘要.md').existsSync(), isTrue);
  });

  test('同名再排一次就覆盖，不会堆出一堆 -2', () async {
    await tool.run(_reportArgs(), _ctx);
    await tool.run(_reportArgs(), _ctx);
    final List<String> names = dir
        .listSync(recursive: true)
        .whereType<File>()
        .map((File f) => f.path.split('/').last)
        .toList();
    expect(names.where((String n) => n.endsWith('.html')).length, 1);
  });

  test('标题里的标签被转义，注入不进去', () async {
    final ToolOutcome out = await tool.run(<String, Object?>{
      'title': '<script>alert(1)</script>',
      'sections': <Object?>[
        <String, Object?>{'level': 'P1', 'heading': 'a<b>', 'body': 'x & y'},
      ],
      'path': 'reports/evil.html',
    }, _ctx);
    expect(out.ok, isTrue, reason: out.error);
    final String page = File('${dir.path}/reports/evil.html').readAsStringSync();
    expect(page, isNot(contains('<script>')));
    expect(page, contains('&lt;script&gt;'));
    expect(page, contains('x &amp; y'));
  });

  test('指标和条目写得不像样也不崩', () async {
    final ToolOutcome out = await tool.run(<String, Object?>{
      'title': 't',
      'metrics': <Object?>['磁盘', 42],
      'sections': <Object?>['随便一句', <String, Object?>{'body': '只有正文'}],
      'path': 'reports/loose.html',
    }, _ctx);
    expect(out.ok, isTrue, reason: out.error);
    final String page = File('${dir.path}/reports/loose.html').readAsStringSync();
    expect(page, contains('只有正文'));
  });

  test('审批卡上念得出报告叫什么', () {
    expect(tool.summarize(<String, Object?>{'title': 'mgr 状态摘要'}), contains('mgr 状态摘要'));
  });
}
