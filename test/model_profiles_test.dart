import 'dart:io';

import 'package:carbide_shell/data/secrets.dart';
import 'package:carbide_shell/data/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('老文件没有 profiles，就按那一个地址和模型名补出第一套', () {
    final AppSettings s = AppSettings.fromJson(<String, Object?>{
      'baseUrl': 'https://api.deepseek.com/v1',
      'model': 'deepseek-chat',
    });
    expect(s.profiles.length, 1);
    expect(s.activeProfile, 'p1');
    expect(s.baseUrl, 'https://api.deepseek.com/v1');
    expect(s.model, 'deepseek-chat');
  });

  test('两套配置写出去再读回来还是一样', () {
    final AppSettings s = AppSettings(
      profiles: <ModelProfile>[
        ModelProfile(
          id: 'p1',
          name: '家里',
          baseUrl: 'http://localhost:11434/v1',
          model: 'qwen2.5',
        ),
        ModelProfile(
          id: 'p2',
          baseUrl: 'https://api.deepseek.com/v1',
          model: 'deepseek-chat',
        ),
      ],
      activeProfile: 'p2',
    );
    expect(s.model, 'deepseek-chat');
    expect(s.profiles.last.label, 'deepseek-chat');

    final AppSettings back = AppSettings.fromJson(s.toJson());
    expect(back.profiles.length, 2);
    expect(back.activeProfile, 'p2');
    expect(back.model, 'deepseek-chat');
    expect(back.profiles.first.name, '家里');
  });

  test('切换配置改的是当前这套，另一套原样不动', () {
    final AppSettings s = AppSettings(
      profiles: <ModelProfile>[
        ModelProfile(id: 'p1', baseUrl: 'https://a/v1', model: 'a-model'),
        ModelProfile(id: 'p2', baseUrl: 'https://b/v1', model: 'b-model'),
      ],
      activeProfile: 'p1',
    );
    s.switchProfile('p2');
    expect(s.model, 'b-model');
    s.model = 'b-model-2';
    expect(s.profiles.first.model, 'a-model');
    expect(s.active.model, 'b-model-2');

    s.switchProfile('没有这个 id');
    expect(s.activeProfile, 'p2');
  });

  test('新建一套是空的，地址不预填，并且立刻切过去', () {
    final AppSettings s = AppSettings(
      baseUrl: 'https://a/v1',
      model: 'a-model',
    );
    final ModelProfile p = s.addProfile();
    expect(p.baseUrl, '');
    expect(p.model, '');
    expect(s.activeProfile, p.id);
    expect(s.baseUrl, '');
    expect(s.profiles.length, 2);
    expect(s.profiles.map((ModelProfile e) => e.id).toSet().length, 2);
  });

  test('删掉一套会把当前切到还在的那套，只剩一套时不删', () {
    final AppSettings s = AppSettings(
      baseUrl: 'https://a/v1',
      model: 'a-model',
    );
    final ModelProfile second = s.addProfile(name: '第二套');
    expect(s.activeProfile, second.id);
    expect(s.removeProfile(second.id), isTrue);
    expect(s.profiles.length, 1);
    expect(s.activeProfile, 'p1');
    expect(s.model, 'a-model');
    expect(s.removeProfile('p1'), isFalse);
    expect(s.profiles.length, 1);
  });

  test('id 空着或重名的配置读进来就补好，切换不会错位', () {
    final AppSettings s = AppSettings.fromJson(<String, Object?>{
      'profiles': <Object?>[
        <String, Object?>{'id': '', 'model': 'one'},
        <String, Object?>{'id': '', 'model': 'two'},
      ],
      'activeProfile': 'p2',
    });
    final List<String> ids = s.profiles.map((ModelProfile p) => p.id).toList();
    expect(ids.toSet().length, 2);
    expect(ids.contains('p2'), isTrue);
    expect(s.model, 'two');
  });

  test('老的那把密钥搬到当前这套配置下，搬完老键删掉', () async {
    final MemorySecretStore secrets = MemorySecretStore();
    await secrets.write(modelSecretKey(), 'sk-old');
    final Directory dir = Directory.systemTemp.createTempSync(
      'carbide_settings',
    );
    final SettingsStore store = SettingsStore(File('${dir.path}/settings.json'))
      ..value = AppSettings(baseUrl: 'https://a/v1', model: 'a-model');

    await store.migrateLegacyKey(secrets);

    expect(await secrets.read(modelSecretKeyFor('p1')), 'sk-old');
    expect(await secrets.read(modelSecretKey()), '');
    dir.deleteSync(recursive: true);
  });
}
