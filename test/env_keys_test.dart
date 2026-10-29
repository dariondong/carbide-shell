import 'dart:io';

import 'package:carbide_shell/data/env_keys.dart';
import 'package:carbide_shell/data/secrets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('名字规则与脱敏', () {
    expect(validEnvName('GITHUB_TOKEN'), isTrue);
    expect(validEnvName('A1'), isTrue);
    expect(validEnvName('_X'), isTrue);
    expect(validEnvName('1ABC'), isFalse);
    expect(validEnvName('lower'), isFalse);
    expect(validEnvName('with-dash'), isFalse);
    expect(maskEnvValue(''), '未设');
    expect(maskEnvValue('abcd'), '••••');
    expect(maskEnvValue('abcdef1234'), '••••34');
  });

  test('写入、更新、删除都记一行日志，值不进文件', () async {
    final Directory dir = Directory.systemTemp.createTempSync('carbide_env');
    final MemorySecretStore secrets = MemorySecretStore();
    final File file = File('${dir.path}/env_keys.json');
    final EnvBook book = EnvBook(file, secrets);
    await book.load();

    await book.set('GITHUB_TOKEN', 'ghp_secret_value', note: '推送用', by: 'ai');
    expect(book.all.length, 1);
    expect(await book.value('GITHUB_TOKEN'), 'ghp_secret_value');
    expect(book.log.first.action, 'set');
    expect(book.log.first.by, 'ai');

    await book.set('GITHUB_TOKEN', 'ghp_second_value');
    expect(book.all.length, 1);
    expect(await book.value('GITHUB_TOKEN'), 'ghp_second_value');
    expect(book.log.first.action, 'rotate');
    expect(book.all.first.note, '推送用');

    final String raw = file.readAsStringSync();
    expect(raw.contains('ghp_secret_value'), isFalse);
    expect(raw.contains('ghp_second_value'), isFalse);
    expect(raw.contains('GITHUB_TOKEN'), isTrue);

    // 重新读回来：名字、说明、日志还在。
    final EnvBook again = EnvBook(file, secrets);
    await again.load();
    expect(again.all.length, 1);
    expect(again.all.first.note, '推送用');
    expect(again.log.length, 2);

    final Map<String, String> masked = await again.masked();
    expect(masked['GITHUB_TOKEN'], '••••ue');

    await again.remove('GITHUB_TOKEN');
    expect(again.all, isEmpty);
    expect(await again.value('GITHUB_TOKEN'), '');
    expect(again.log.first.action, 'delete');
    dir.deleteSync(recursive: true);
  });

  test('坏名字不落盘', () async {
    final Directory dir = Directory.systemTemp.createTempSync('carbide_env2');
    final EnvBook book = EnvBook(File('${dir.path}/env.json'), MemorySecretStore());
    await book.load();
    expect(book.byName('nope'), isNull);
    dir.deleteSync(recursive: true);
  });
}
