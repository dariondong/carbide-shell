import '../core/models.dart';
import '../core/tools.dart';
import '../data/foreground.dart';

/// `notify`：让模型弹一条系统通知。
///
/// 只有安卓有这一套。别的平台、或者用户把通知关掉了，都如实说没弹，
/// 不假装发过，也不让一条通知把整轮活拖死。
class NotifyTool extends Tool {
  /// 连着弹几条时各占一格，后一条不要盖掉前一条。
  static int _slot = 0;

  @override
  String get name => 'notify';

  @override
  String get description =>
      '弹一条系统通知：一个标题加一句话。用户切出应用、锁了屏也能看到。'
      '有安卓通知才发得出去，别的平台会如实回一句没弹。'
      '要在跑完之后提醒人、或者要人回来处理一件事，用这个。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'title': <String, Object?>{
            'type': 'string',
            'description': '通知的标题，短一些，比如 备份跑完了',
          },
          'text': <String, Object?>{
            'type': 'string',
            'description': '正文，一句话说清是什么事、要人做什么',
          },
        },
        'required': <String>['text'],
      };

  /// 弹一条提示不改任何东西，不拦。
  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.read;

  @override
  String summarize(Map<String, Object?> args) {
    final String title = readString(args, 'title').trim();
    final String text = readString(args, 'text').trim();
    return '弹通知${title.isEmpty ? '' : '「$title」'}${text.isEmpty ? '' : '：$text'}';
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String text = readString(args, 'text').trim();
    if (text.isEmpty) {
      return const ToolOutcome.failure('通知得写一句话，写在 text 里。');
    }
    if (!ForegroundTask.supported) {
      return const ToolOutcome.failure(
          '这台平台上没有系统通知，只有安卓能弹。要提醒人就写在回答里。');
    }
    final NotifyState state = await ForegroundTask.state();
    if (!state.ready) {
      return ToolOutcome.failure(
          '通知现在发不出去：${state.text}。让人去设置里打开，或者把这件事写在回答里。');
    }
    final String title = readString(args, 'title').trim();
    _slot = (_slot + 1) % 32;
    await ForegroundTask.alert(title, text, slot: _slot);
    return ToolOutcome.success(stdout: '弹了一条通知：${title.isEmpty ? text : title}');
  }
}
