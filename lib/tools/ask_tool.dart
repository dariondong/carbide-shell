import '../core/models.dart';
import '../core/tools.dart';

/// 模型想向人确认一件事时递上来的一张卡。
class AskRequest {
  const AskRequest({required this.question, this.options = const <String>[]});

  final String question;

  /// 可以选的那几项。空着表示让人自己写。
  final List<String> options;
}

/// 谁来回答。[AskTool] 拿到回答才返回，所以一轮会停在这里等人。
typedef AskResolver = Future<String> Function(AskRequest request);

/// `ask`：把一个问题递给人，等人回答再往下走。
///
/// 对话里有界面可以把问题摆出来；定时任务跑的时候没有人看着，就如实告诉模型
/// 没有人回答，让它自己拿主意。
class AskTool extends Tool {
  AskTool({this.resolver});

  AskResolver? resolver;

  @override
  String get name => 'ask';

  @override
  String get description =>
      '问用户一个问题，等回答再继续。改东西之前拿不准、需要人挑一个方案、或者缺一个只有用户知道的值时用这个，不要自己猜。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'question': <String, Object?>{'type': 'string', 'description': '一句话问清楚'},
          'options': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
            'description': '可选项，最多四个。给了就是让人挑一个，不给人可以自己写。',
          },
        },
        'required': <String>['question'],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.read;

  @override
  String summarize(Map<String, Object?> args) => '问：${readString(args, 'question')}';

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String question = readString(args, 'question').trim();
    if (question.isEmpty) return const ToolOutcome.failure('问题不能是空的。');
    final Object? raw = args['options'];
    final List<String> options = <String>[];
    if (raw is List) {
      for (final Object? item in raw) {
        final String text = '$item'.trim();
        if (text.isNotEmpty && options.length < 4) options.add(text);
      }
    }
    final AskResolver? who = resolver;
    if (who == null) {
      return const ToolOutcome.success(
        stdout: '没有人回答这个问题：现在没有人看着这个对话。'
            '按你自己的判断继续，在结论里说清楚你假设了什么。',
      );
    }
    final String answer = (await who(AskRequest(question: question, options: options))).trim();
    if (answer.isEmpty) {
      return const ToolOutcome.failure('用户没有回答。');
    }
    return ToolOutcome.success(stdout: '用户回答：$answer');
  }
}
