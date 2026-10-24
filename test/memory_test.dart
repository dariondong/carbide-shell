import 'dart:io';

import 'package:carbide_shell/core/memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('carbide_mem');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('写进去之后另一份实例能读回来', () async {
    final File file = File('${dir.path}/memory.json');
    final MemoryStore store = MemoryStore(file);
    await store.load();
    await store.add('用户偏好中文回答', tag: '偏好');

    final MemoryStore again = MemoryStore(file);
    await again.load();
    expect(again.entries.length, 1);
    expect(again.entries.first.text, '用户偏好中文回答');
    expect(again.entries.first.tag, '偏好');
  });

  test('改一条和删一条', () async {
    final MemoryStore store = MemoryStore(File('${dir.path}/memory.json'));
    await store.load();
    final MemoryEntry e = await store.add('旧的');
    await store.update(e.id, text: '新的', tag: '规则');
    expect(store.entries.first.text, '新的');
    expect(store.entries.first.tag, '规则');
    await store.remove(e.id);
    expect(store.entries, isEmpty);
  });

  test('空内容不写', () async {
    final MemoryStore store = MemoryStore(File('${dir.path}/memory.json'));
    await store.load();
    await store.add('   ');
    expect(store.entries, isEmpty);
  });

  test('提示文本带分类和目录，多条按时间正序', () async {
    final MemoryStore store = MemoryStore(File('${dir.path}/memory.json'));
    await store.load();
    await store.add('第一条', tag: '主机');
    await store.add('第二条');
    final String prompt = store.renderForPrompt();
    expect(prompt.contains('[主机] 第一条'), isTrue);
    expect(prompt.indexOf('第一条') < prompt.indexOf('第二条'), isTrue);
  });

  test('超出字数上限时保留最新的', () async {
    final MemoryStore store = MemoryStore(File('${dir.path}/memory.json'));
    await store.load();
    for (int i = 0; i < 30; i += 1) {
      await store.add('第$i条 ${'x' * 40}');
    }
    final String prompt = store.renderForPrompt(maxChars: 300);
    expect(prompt.length < 500, isTrue);
    expect(prompt.contains('第29条'), isTrue);
    expect(prompt.contains('第0条'), isFalse);
  });

  test('文件坏了也不影响启动', () async {
    final File file = File('${dir.path}/memory.json');
    file.writeAsStringSync('{ this is not json');
    final MemoryStore store = MemoryStore(file);
    await store.load();
    expect(store.entries, isEmpty);
  });
}
