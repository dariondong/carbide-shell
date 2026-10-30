import 'dart:io';

import 'package:carbide_shell/core/memory.dart';
import 'package:carbide_shell/core/models.dart';
import 'package:carbide_shell/tools/memory_tool.dart';
import 'package:flutter_test/flutter_test.dart';

const ToolContext _ctx = ToolContext(workspace: '/tmp', desktop: true);

void main() {
  late Directory dir;
  late MemoryStore store;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('cbs-mem');
    store = MemoryStore(File('${dir.path}/global.json'));
    await store.load();
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('长期记忆', () {
    test('空的就如实说空', () async {
      final ToolOutcome out = await MemoryTool(store).run(<String, Object?>{}, _ctx);
      expect(out.ok, isTrue);
      expect(out.stdout, contains('空的'));
    });

    test('加一条之后 list 会带上 id', () async {
      final ToolOutcome added = await MemoryTool(store)
          .run(<String, Object?>{'action': 'add', 'text': '喜欢短句子', 'tag': '偏好'}, _ctx);
      expect(added.ok, isTrue);
      expect(store.length, 1);
      final String id = store.entries.first.id;
      expect(added.stdout, contains(id));

      final ToolOutcome listed =
          await MemoryTool(store).run(<String, Object?>{'action': 'list'}, _ctx);
      expect(listed.stdout, contains(id));
      expect(listed.stdout, contains('[偏好] 喜欢短句子'));
    });

    test('按 id 改写还是那一条，不新增', () async {
      await store.add('磁盘在 /dev/sda1', tag: '主机');
      final String id = store.entries.first.id;
      final ToolOutcome out = await MemoryTool(store)
          .run(<String, Object?>{'action': 'update', 'id': id, 'text': '磁盘在 /dev/nvme0n1'}, _ctx);
      expect(out.ok, isTrue);
      expect(store.length, 1);
      expect(store.entries.first.text, '磁盘在 /dev/nvme0n1');
      expect(store.entries.first.tag, '主机', reason: '没给的字段不该被清掉');
    });

    test('id 只抄开头一段也认', () async {
      await store.add('这条要改');
      final String id = store.entries.first.id;
      final ToolOutcome out = await MemoryTool(store)
          .run(<String, Object?>{'action': 'update', 'id': id.substring(0, 6), 'tag': '规则'}, _ctx);
      expect(out.ok, isTrue);
      expect(store.entries.first.tag, '规则');
      expect(store.entries.first.text, '这条要改');
    });

    test('删掉一条就真的不在了', () async {
      await store.add('第一条');
      await store.add('第二条');
      final String keep = store.entries.first.id;
      final ToolOutcome out = await MemoryTool(store)
          .run(<String, Object?>{'action': 'delete', 'id': keep}, _ctx);
      expect(out.ok, isTrue);
      expect(store.length, 1);
      expect(store.entries.first.text, '第一条');
    });

    test('找不到那一 id 就拒绝，并把现有几条念出来', () async {
      await store.add('只剩这条');
      final ToolOutcome out = await MemoryTool(store)
          .run(<String, Object?>{'action': 'delete', 'id': 'mXXXXXX'}, _ctx);
      expect(out.ok, isFalse);
      expect(out.error, contains('没有这一条'));
      expect(out.error, contains('只剩这条'));
      expect(store.length, 1);
    });

    test('改和删没给 id 就说没给', () async {
      final ToolOutcome upd = await MemoryTool(store)
          .run(<String, Object?>{'action': 'update', 'text': '随便'}, _ctx);
      expect(upd.ok, isFalse);
      final ToolOutcome del =
          await MemoryTool(store).run(<String, Object?>{'action': 'delete'}, _ctx);
      expect(del.ok, isFalse);
    });

    test('改完写进文件，重新读回来还是新的', () async {
      await store.add('旧的一句话');
      final String id = store.entries.first.id;
      await MemoryTool(store)
          .run(<String, Object?>{'action': 'update', 'id': id, 'text': '新的一句话'}, _ctx);
      final MemoryStore again = MemoryStore(File('${dir.path}/global.json'));
      await again.load();
      expect(again.entries.first.text, '新的一句话');
    });

    test('看和改算读，删算写', () {
      final MemoryTool tool = MemoryTool(store);
      expect(tool.classify(<String, Object?>{}), ToolRisk.read);
      expect(tool.classify(<String, Object?>{'action': 'add', 'text': 'a'}), ToolRisk.read);
      expect(tool.classify(<String, Object?>{'action': 'update', 'id': 'm1'}), ToolRisk.read);
      expect(tool.classify(<String, Object?>{'action': 'delete', 'id': 'm1'}), ToolRisk.write);
    });
  });
}
