import 'package:carbide_shell/core/params.dart';
import 'package:carbide_shell/data/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('参数取值范围与写法', () {
    final ParamSpec spec = paramSpecOf('temperature')!;
    expect(spec.fallback, 0.2);
    expect(spec.span, '0–2');
    expect(spec.format(0.7), '0.7');
    expect(spec.format(1), '1');
    expect(paramSpecOf('nope'), isNull);
  });

  test('AI 调参数：超范围、锁着都改不动', () {
    final Map<String, ParamState> params = <String, ParamState>{};
    ParamEdit edit = applyParam(params,
        key: 'temperature',
        value: 0.7,
        range: const ParamRange(0, 2),
        byAi: true,
        reason: '长文本');
    expect(edit.ok, isTrue);
    expect(params['temperature']!.value, 0.7);
    expect(params['temperature']!.source, 'ai');
    expect(edit.text, contains('0.2 → 0.7'));

    edit = applyParam(params,
        key: 'temperature', value: 3, range: const ParamRange(0, 2), byAi: true);
    expect(edit.ok, isFalse);
    expect(edit.text, contains('超了'));

    setParamLock(params, key: 'temperature', locked: true);
    edit = applyParam(params,
        key: 'temperature', value: 0.4, range: const ParamRange(0, 2), byAi: true);
    expect(edit.ok, isFalse);
    expect(edit.text, contains('锁着'));

    // 用户自己填不受锁影响，来源记成手动。
    edit = applyParam(params,
        key: 'temperature', value: 0.4, range: const ParamRange(0, 2), byAi: false);
    expect(edit.ok, isTrue);
    expect(params['temperature']!.source, 'user');

    resetParam(params, key: 'temperature');
    expect(params['temperature']!.value, 0.2);
    expect(params['temperature']!.source, isEmpty);
    expect(params['temperature']!.locked, isTrue);
  });

  test('允许范围可以被设置改窄，读坏的回落到出厂', () {
    final ParamRange narrow = paramRangeOf('temperature', overrides: <String, List<double>>{
      'temperature': <double>[0.1, 1.2],
    });
    expect(narrow.low, 0.1);
    expect(narrow.high, 1.2);
    final ParamRange bogus = paramRangeOf('temperature', overrides: <String, List<double>>{
      'temperature': <double>[1.5, 0.5],
    });
    expect(bogus.low, 0);
    expect(bogus.high, 2);
  });

  test('提示词、参数、报价跟着配置走', () {
    final AppSettings s = AppSettings(
      profiles: <ModelProfile>[
        ModelProfile(id: 'p1', name: '日常', baseUrl: 'https://a', model: 'm1'),
        ModelProfile(id: 'p2', name: '长文', baseUrl: 'https://b', model: 'm2'),
      ],
      activeProfile: 'p1',
      paramRanges: <String, List<double>>{
        'temperature': <double>[0, 1.5],
      },
    );
    s.profileById('p2')!
      ..prompt = '你是长文助手'
      ..userPrompt = '说得短一点';
    applyParam(s.profileById('p2')!.params,
        key: 'temperature', value: 1.1, range: s.paramRange('temperature'));

    final AppSettings back = AppSettings.fromJson(s.toJson());
    expect(back.profiles.length, 2);
    expect(back.profileById('p2')!.prompt, '你是长文助手');
    expect(back.profileById('p2')!.userPrompt, '说得短一点');
    expect(back.profileById('p2')!.paramValue('temperature'), 1.1);
    expect(back.paramRange('temperature').high, 1.5);
    expect(back.temperatureFor(back.profileById('p2')!), 1.1);
    expect(back.temperatureFor(back.profileById('p1')!), 0.2);
  });

  test('复制一份配置，参数各改各的', () {
    final AppSettings s = AppSettings(
      profiles: <ModelProfile>[
        ModelProfile(id: 'p1', baseUrl: 'https://a', model: 'm1', prompt: '内置那份'),
      ],
    );
    applyParam(s.active.params, key: 'temperature', value: 1.1, range: s.paramRange('temperature'));
    final ModelProfile copy = s.duplicateProfile('p1');
    expect(copy.id, isNot('p1'));
    expect(copy.label, endsWith('副本'));
    expect(copy.prompt, '内置那份');
    copy.params['temperature']!.value = 0.5;
    expect(s.active.params['temperature']!.value, 1.1);
  });

  test('设为默认与配置是否配完', () {
    final AppSettings s = AppSettings(
      profiles: <ModelProfile>[
        ModelProfile(id: 'p1', baseUrl: 'https://a', model: 'm1'),
        ModelProfile(id: 'p2', baseUrl: 'https://b', model: 'm2'),
      ],
    );
    expect(s.setDefault('p2'), isTrue);
    expect(s.activeProfile, 'p2');
    expect(s.setDefault('nope'), isFalse);
    expect(s.active.complete, isTrue);
    expect(ModelProfile(id: 'x').complete, isFalse);
  });
}
