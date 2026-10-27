import '../core/models.dart';
import '../core/report.dart';
import '../core/tools.dart';
import '../data/temp_files.dart';

/// `report_render`：把十几个数字和几段话排成一份报告，落到临时文件区。
///
/// 报告的内容本来就只有那么点，每次手敲整篇带行内样式的 HTML，费的是 token，
/// 换来的是前后不一致。排版固定在这里，模型只给内容。
class ReportRenderTool extends Tool {
  ReportRenderTool(this.files);

  final TempFiles files;

  @override
  String get name => 'report_render';

  @override
  String get description =>
      '把标题、几个指标、几段说明排成一份报告文件，写进临时文件区。'
      'template=email 是纯 table 加全行内样式，Gmail 和 Outlook 都认；'
      'template=report 是网页版，手机上好读；template=plain 是 Markdown 纯文本。'
      '要写报告别手敲整篇 HTML，把内容给它就行。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'title': <String, Object?>{'type': 'string', 'description': '报告标题'},
          'subtitle': <String, Object?>{
            'type': 'string',
            'description': '副标题，通常写主机名和日期',
          },
          'template': <String, Object?>{
            'type': 'string',
            'enum': <String>['report', 'email', 'plain'],
            'description': '默认 report',
          },
          'metrics': <String, Object?>{
            'type': 'array',
            'description': '顶部那排大号数字，最多四个一行',
            'items': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'value': <String, Object?>{'type': 'string'},
                'label': <String, Object?>{'type': 'string'},
                'tone': <String, Object?>{
                  'type': 'string',
                  'enum': <String>['ok', 'warn', 'bad', 'plain', 'accent'],
                },
              },
              'required': <String>['value', 'label'],
            },
          },
          'sections': <String, Object?>{
            'type': 'array',
            'description': '一条一个问题，或者一条一个提示框',
            'items': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'heading': <String, Object?>{'type': 'string'},
                'body': <String, Object?>{'type': 'string', 'description': '断行原样留着'},
                'level': <String, Object?>{
                  'type': 'string',
                  'description': 'P0 / P1 / P2，有它就出一个彩色标签',
                },
                'kind': <String, Object?>{'type': 'string', 'description': 'note 是提示框'},
                'color': <String, Object?>{
                  'type': 'string',
                  'enum': <String>['amber', 'red', 'green', 'blue'],
                },
              },
              'required': <String>['heading'],
            },
          },
          'footer': <String, Object?>{'type': 'string', 'description': '页脚一句，比如数据来源'},
          'path': <String, Object?>{
            'type': 'string',
            'description': '临时文件区里的相对路径；留空按标题落在 reports/ 下',
          },
          'inline': <String, Object?>{
            'type': 'boolean',
            'description': '排好的内容也直接回一份。纯文本默认回，网页版默认不回',
          },
        },
        'required': <String>['title'],
      };

  /// 只是往临时文件区写一份报告，不动主机。
  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.read;

  @override
  String summarize(Map<String, Object?> args) {
    final String title = readString(args, 'title').trim();
    return '排报告${title.isEmpty ? '' : '「$title」'}';
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String title = readString(args, 'title').trim();
    if (title.isEmpty) return const ToolOutcome.failure('报告得有个 title。');
    final String template = readString(args, 'template', fallback: 'report').trim().toLowerCase();
    final String kind = template == 'plain' ? 'plain' : (template == 'email' ? 'email' : 'report');
    final String text = renderReport(
      template: kind,
      title: title,
      subtitle: readString(args, 'subtitle'),
      metrics: _metrics(args['metrics']),
      sections: _sections(args['sections']),
      footer: readString(args, 'footer'),
    );
    final String path = readString(args, 'path').trim();
    final bool inline = args['inline'] is bool ? args['inline']! as bool : kind == 'plain';
    final String target = path.isNotEmpty
        ? path
        : 'reports/${_slug(title)}.${kind == 'plain' ? 'md' : 'html'}';
    final StringBuffer out = StringBuffer();
    try {
      final TempFile saved = await files.saveText(target, text);
      out.writeln('写好了：${saved.path}（${_size(saved.size)}，${text.length} 字符）');
    } catch (e) {
      return ToolOutcome.failure('报告没写下去：$e');
    }
    if (inline) {
      out.writeln();
      out.write(text);
    } else if (kind != 'plain') {
      out.write('邮件版可以拿这份当正文发出去（mail_send 的 html_path 指它）。');
    }
    return ToolOutcome.success(
      stdout: out.toString(),
      meta: <String, Object?>{
        'path': target,
        'template': kind,
        'chars': text.length,
      },
    );
  }

  List<ReportMetric> _metrics(Object? raw) {
    if (raw is! List) return const <ReportMetric>[];
    final List<ReportMetric> out = <ReportMetric>[];
    for (final Object? item in raw) {
      if (item is! Map) continue;
      final String value = _s(item['value']);
      final String label = _s(item['label']);
      if (value.isEmpty && label.isEmpty) continue;
      final String tone = _s(item['tone']).toLowerCase();
      out.add(ReportMetric(
        value: value,
        label: label,
        tone: const <String>{'ok', 'warn', 'bad', 'plain', 'accent'}.contains(tone)
            ? tone
            : 'plain',
      ));
    }
    return out;
  }

  List<ReportSection> _sections(Object? raw) {
    if (raw is! List) return const <ReportSection>[];
    final List<ReportSection> out = <ReportSection>[];
    for (final Object? item in raw) {
      if (item is! Map) continue;
      final String heading = _s(item['heading']);
      final String body = _s(item['body']);
      if (heading.isEmpty && body.isEmpty) continue;
      final String level = _s(item['level']).toUpperCase();
      out.add(ReportSection(
        heading: heading,
        body: body,
        level: const <String>{'P0', 'P1', 'P2'}.contains(level) ? level : '',
        kind: _s(item['kind']).toLowerCase() == 'note' ? 'note' : '',
        color: _s(item['color']).toLowerCase(),
      ));
    }
    return out;
  }

  String _s(Object? v) => v is String ? v.trim() : (v == null ? '' : '$v'.trim());

  /// 标题当文件名用：洗一遍，太长就砍，砍到空就叫 report。
  String _slug(String title) {
    final String cleaned = TempFiles.cleanPath(title.replaceAll('/', '-'));
    final String flat = cleaned.replaceAll('/', '-');
    if (flat.isEmpty) return 'report';
    return flat.length > 40 ? flat.substring(0, 40) : flat;
  }

  String _size(int bytes) =>
      bytes < 1024 ? '$bytes B' : '${(bytes / 1024).toStringAsFixed(1)} KB';
}
