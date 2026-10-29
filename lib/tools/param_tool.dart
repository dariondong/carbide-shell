import '../core/models.dart';
import '../core/params.dart';
import '../core/tools.dart';
import '../data/settings.dart';

/// `tune_param`：模型提出把某个参数调一调，用户点批准才真的改。
///
/// 三道闸都在这里：用户没让 AI 调、参数锁着、值超出现在允许的范围。
/// 过了一道也不直接写盘，得先过审批卡。
class TuneParamTool extends Tool {
  TuneParamTool({
    required this.settings,
    required this.profileId,
    required this.save,
  });

  final SettingsStore settings;

  /// 这场对话钉在哪套配置上。
  final String Function() profileId;

  /// 落盘。设置页那边用的是同一个存法。
  final Future<void> Function() save;

  @override
  String get name => 'tune_param';

  @override
  String get description =>
      '建议把这套模型配置的某个参数改一改（目前只有 temperature 温度）。'
      '用户点批准之后才生效；参数被用户锁住、或者超出允许范围，会直接回一句改不了。'
      '只有在当前参数明显不合适时才提，一次只提一个参数，并在 reason 里写清为什么。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'key': <String, Object?>{
            'type': 'string',
            'description': '参数名，例如 temperature',
            'enum': kParamSpecs.map((ParamSpec s) => s.key).toList(),
          },
          'value': <String, Object?>{
            'type': 'number',
            'description': '想改成多少',
          },
          'reason': <String, Object?>{
            'type': 'string',
            'description': '为什么改，一句话，用户会在批准卡上看到',
          },
        },
        'required': <String>['key', 'value'],
      };

  @override
  bool get alwaysAsk => true;

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.write;

  @override
  String summarize(Map<String, Object?> args) {
    final String key = readString(args, 'key').trim();
    final ParamSpec? spec = paramSpecOf(key);
    final double? value = readNumber(args, 'value');
    if (spec == null || value == null) return '调参数';
    return '把${spec.label}调成 ${spec.format(value)}';
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final AppSettings s = settings.value;
    if (!s.aiTune) {
      return const ToolOutcome.failure(
          '用户关掉了「允许 AI 调节参数」，这次没有改。要改就在设置 → 模型里自己填。');
    }
    final String key = readString(args, 'key').trim();
    final ParamSpec? spec = paramSpecOf(key);
    if (spec == null) {
      return ToolOutcome.failure(
          '没有这个参数：$key。能调的是 ${kParamSpecs.map((ParamSpec p) => p.key).join('、')}。');
    }
    final double? value = readNumber(args, 'value');
    if (value == null) return const ToolOutcome.failure('value 得是个数。');
    final String reason = readString(args, 'reason').trim();
    final ModelProfile profile = s.profileById(profileId()) ?? s.active;
    final ParamEdit edit = applyParam(
      profile.params,
      key: key,
      value: value,
      range: s.paramRange(key),
      byAi: true,
      reason: reason,
    );
    if (!edit.ok) return ToolOutcome.failure(edit.text);
    await save();
    final String at = profile.params[key]?.at ?? '';
    return ToolOutcome.success(
      stdout: '改好了：${profile.label} 的${edit.text}。'
          '${edit.state?.locked == true ? '这个参数锁着，本来不该动，请用户看一眼。' : ''}'
          '${at.isEmpty ? '' : ''}',
    );
  }
}
