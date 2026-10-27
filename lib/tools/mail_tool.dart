import '../core/models.dart';
import '../core/smtp.dart';
import '../core/tools.dart';
import '../data/mail.dart';
import '../data/temp_files.dart';

/// `mail_send`：让模型用设置里那个邮箱发一封通知邮件。
///
/// 收件人、发件人、密码都在设置页里，模型只能写主题和正文。没配全就如实说，
/// 不假装发过。发出去收不回来，所以归到写操作，过一道确认。
class MailSendTool extends Tool {
  MailSendTool(this.mail, {this.files});

  final MailStore mail;

  /// 临时文件区：可以让正文的 HTML 版取自那里的一整页（`report_render` 写出来的）。
  final TempFiles? files;

  @override
  String get name => 'mail_send';

  @override
  String get description =>
      '用设置里配好的邮箱发一封通知邮件：写主题和正文就行，发给谁由设置决定。'
      '要把结果送出去、或者用户不在手机前面时，用这个。没配好会如实回一句。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'subject': <String, Object?>{
            'type': 'string',
            'description': '主题，短一些；留空就取正文第一行',
          },
          'body': <String, Object?>{
            'type': 'string',
            'description': '正文，几行都行。机器名和时间会自动接在后面',
          },
          'html_path': <String, Object?>{
            'type': 'string',
            'description': '临时文件区里一页 HTML，当这封信的富文本版；留空就按正文自动排一版',
          },
        },
        'required': <String>['body'],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.write;

  @override
  String summarize(Map<String, Object?> args) {
    final String subject = readString(args, 'subject').trim();
    return '发邮件${subject.isEmpty ? '' : '「$subject」'}';
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String body = readString(args, 'body').trim();
    if (body.isEmpty) {
      return const ToolOutcome.failure('邮件总得有正文，写在 body 里。');
    }
    final Mailer mailer = Mailer(mail);
    if (!mailer.ready) {
      final String missing = mail.value.missing;
      return ToolOutcome.failure(
          '邮件发不出去：${missing.isEmpty ? '设置里没配好' : missing}。'
          '让人去设置里把邮箱填上，或者把内容写在回答里。');
    }
    String subject = readString(args, 'subject').trim();
    if (subject.isEmpty) {
      final String first = body.split('\n').first.trim();
      subject = first.length > 40 ? '${first.substring(0, 40)}…' : first;
    }
    // 指定了一整页 HTML 就拿它当富文本版，没指定就按正文自己排。
    String html = '';
    final String htmlPath = readString(args, 'html_path').trim();
    if (htmlPath.isNotEmpty) {
      final String? page = await files?.readText(htmlPath);
      if (page == null || page.trim().isEmpty) {
        return ToolOutcome.failure('临时区里读不出这一页：$htmlPath。要不要改成不带 html_path 发。');
      }
      html = page;
    }
    final SmtpResult result =
        await mailer.send(subject, mailBody(line: body, detail: ''), html: html);
    if (!result.ok) return ToolOutcome.failure('邮件没发出去：${result.error}');
    final int count = mail.value.recipients.length;
    return ToolOutcome.success(stdout: '发出去了：$subject（$count 个收件人）');
  }
}
