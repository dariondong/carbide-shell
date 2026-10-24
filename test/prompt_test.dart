import 'dart:io';

import 'package:carbide_shell/core/agent.dart';
import 'package:carbide_shell/core/conversation.dart';
import 'package:carbide_shell/data/activity.dart';
import 'package:carbide_shell/data/settings.dart';
import 'package:carbide_shell/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('carbide_prompt');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('系统提示词用哪一份', () {
    test('都没有就是内置那份', () {
      final SettingsStore settings = SettingsStore(File('${dir.path}/settings.json'));
      final Conversation c = Conversation(id: 'c1', title: 't', hostId: '');
      expect(promptFor(settings, c), kSystemPrompt);
    });

    test('设置里写了就用设置里的', () {
      final SettingsStore settings = SettingsStore(File('${dir.path}/settings.json'));
      settings.value.systemPrompt = '你是机房的老张，说话短。';
      final Conversation c = Conversation(id: 'c1', title: 't', hostId: '');
      expect(promptFor(settings, c), '你是机房的老张，说话短。');
    });

    test('对话自己写的那份盖过设置', () {
      final SettingsStore settings = SettingsStore(File('${dir.path}/settings.json'));
      settings.value.systemPrompt = '设置里那份';
      final Conversation c = Conversation(id: 'c1', title: 't', hostId: '')
        ..systemPrompt = '这个对话那份';
      expect(promptFor(settings, c), '这个对话那份');
    });

    test('空白当没写', () {
      final SettingsStore settings = SettingsStore(File('${dir.path}/settings.json'));
      settings.value.systemPrompt = '   ';
      final Conversation c = Conversation(id: 'c1', title: 't', hostId: '')
        ..systemPrompt = '\n  ';
      expect(promptFor(settings, c), kSystemPrompt);
    });
  });

  group('对话自己的提示词存得住', () {
    test('写了才落盘，没写就不占字段', () {
      final Conversation plain = Conversation(id: 'c1', title: 't', hostId: '');
      expect(plain.toJson().containsKey('systemPrompt'), isFalse);
      final Conversation own = Conversation(id: 'c2', title: 't', hostId: '')
        ..systemPrompt = '只认中文';
      final Map<String, Object?> json = own.toJson();
      expect(json['systemPrompt'], '只认中文');
      expect(Conversation.fromJson(json).systemPrompt, '只认中文');
    });
  });

  group('忙碌看板', () {
    test('一件写一件，两件写「2 个在忙」', () {
      final ActivityBoard board = ActivityBoard();
      expect(board.any, isFalse);
      expect(board.text, '');

      board.note('c:1', '磁盘清理 · 第 2/12 步 · 执行命令');
      expect(board.count, 1);
      expect(board.text, '磁盘清理 · 第 2/12 步 · 执行命令');

      board.note('t:9', '体检 · 开跑');
      expect(board.count, 2);
      expect(board.text, '2 个在忙 · 体检 · 开跑');

      board.done('t:9', summary: '体检 · 跑完了');
      expect(board.text, '磁盘清理 · 第 2/12 步 · 执行命令');

      board.done('c:1');
      expect(board.any, isFalse);
      expect(board.text, '');
    });

    test('收掉一件不在的事也不炸', () {
      final ActivityBoard board = ActivityBoard();
      board.done('c:404');
      expect(board.any, isFalse);
    });

    test('同一个 key 只占一位', () {
      final ActivityBoard board = ActivityBoard();
      board.note('c:1', '第一步');
      board.note('c:1', '第二步');
      expect(board.count, 1);
      expect(board.text, '第二步');
    });
  });
}
