import '../core/html_check.dart';
import '../core/models.dart';
import '../core/tools.dart';
import '../data/temp_files.dart';

/// `render_check`：看一眼一份 HTML 会不会被邮件客户端剥掉或者撑破。
///
/// 手机上没有浏览器内核可开，所以这里不截图，也不下「看起来怎么样」的结论，
/// 只报能数出来的事实：标签配不配平、行内样式占多少、有没有外链、有没有超宽。
class RenderCheckTool extends Tool {
  RenderCheckTool(this.files);

  final TempFiles files;

  @override
  String get name => 'render_check';

  @override
  String get description =>
      '体检一份 HTML：标签配不配平、行内样式覆盖率、有没有 <style> / <script> / 外链样式和图片、'
      '有没有超过 640 的固定宽度。不截图，也不判断好不好看，只回能数出来的事。'
      '路径可以指临时文件区里的文件，也可以直接把 HTML 放在 html 里。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'path': <String, Object?>{
            'type': 'string',
            'description': '临时文件区里的相对路径，比如 reports/mgr.html',
          },
          'html': <String, Object?>{'type': 'string', 'description': '不给路径就直接查这段 HTML'},
          'email': <String, Object?>{
            'type': 'boolean',
            'description': '按邮件客户端的脾气判，默认 true；网页版报 false',
          },
        },
      };

  /// 只读一份文件。
  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.read;

  @override
  String summarize(Map<String, Object?> args) {
    final String path = readString(args, 'path').trim();
    return '体检${path.isEmpty ? '一段 HTML' : ' $path'}';
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String path = readString(args, 'path').trim();
    final bool email = args['email'] is bool ? args['email']! as bool : true;
    String html = readString(args, 'html');
    if (path.isNotEmpty) {
      final String? text = await files.readText(path);
      if (text == null) {
        return ToolOutcome.failure('临时区里读不出这个文件：$path（不存在，或者不是文本）。');
      }
      html = text;
    }
    if (html.trim().isEmpty) {
      return const ToolOutcome.failure('给一个 path，或者把 HTML 放在 html 里。');
    }
    final HtmlReport report = checkHtml(html, email: email);
    final String text = htmlReportText(report, path: path);
    return ToolOutcome.success(
      stdout: '$text\n（只数得出来这些；截图要浏览器内核，手机上没有。）',
      meta: <String, Object?>{
        'bytes': report.bytes,
        'elements': report.elements,
        'inline': report.inlineStyled,
        'warnings': report.issues.where((HtmlIssue i) => i.level == 'warn').length,
      },
    );
  }
}
