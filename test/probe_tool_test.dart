import 'dart:io';

import 'package:carbide_shell/core/models.dart';
import 'package:carbide_shell/tools/probe_tool.dart';
import 'package:flutter_test/flutter_test.dart';

const ToolContext _ctx = ToolContext(workspace: '/tmp', desktop: true);

void main() {
  final ProbeTool tool = ProbeTool();

  test('没给地址就说没给', () async {
    final ToolOutcome out = await tool.run(<String, Object?>{'port': 80}, _ctx);
    expect(out.ok, isFalse);
    expect(out.error, contains('host'));
  });

  test('端口越界就说越界，不去连', () {
    final ToolOutcome out = await tool.run(<String, Object?>{
      'host': '127.0.0.1',
      'port': 70000,
    }, _ctx);
    expect(out.stdout, contains('不在 1-65535'));
    expect(out.meta['reachable'], isFalse);
  });

  test('开着的端口握手成功，回毫秒数', () async {
    final ServerSocket server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close());
    final ToolOutcome out = await tool.run(<String, Object?>{
      'host': '127.0.0.1',
      'port': server.port,
      'timeout_seconds': 2,
    }, _ctx);
    expect(out.ok, isTrue);
    expect(out.meta['reachable'], isTrue);
    expect(out.stdout, contains('通'));
    expect(out.stdout, contains('ms'));
  });

  test('关着的端口给出不通和原因', () async {
    final ServerSocket spare = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final int port = spare.port;
    await spare.close();
    final ToolOutcome out = await tool.run(<String, Object?>{
      'host': '127.0.0.1',
      'port': port,
      'timeout_seconds': 2,
    }, _ctx);
    expect(out.meta['reachable'], isFalse);
    expect(out.stdout, contains('不通'));
    expect((out.meta['error'] as String).isNotEmpty, isTrue);
  });

  test('解析不了的域名也不炸', () async {
    final ToolOutcome out = await tool.run(<String, Object?>{
      'host': 'no-such-host.invalid',
      'port': 80,
      'timeout_seconds': 2,
    }, _ctx);
    expect(out.meta['reachable'], isFalse);
    expect((out.meta['error'] as String).isNotEmpty, isTrue);
  });

  test('审批卡上念得出测的是哪个端口', () {
    expect(tool.summarize(<String, Object?>{'host': 'a.example', 'port': 443}), contains('443'));
  });

  test('只握手，不算写操作', () {
    expect(tool.classify(<String, Object?>{'host': 'a', 'port': 1}), ToolRisk.read);
  });
}
