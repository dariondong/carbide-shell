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
      '用设置里配好的邮箱发一封通知邮件。发给谁由你选：可选范围是设置里允许的那几个地址，'
      '不填就发给默认收件人。发送前用户会看到收件人和你的理由，他点批准才发。'
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
          'to': <String, Object?>{
            'type': 'string',
            'description': '收件人，必须是设置里允许的地址之一；不填就用默认收件人',
          },
          'why': <String, Object?>{
            'type': 'string',
            'description': '为什么发给他，一句话，用户会在确认卡上看到',
          },
          'html_path': <String, Object?>{
            'type': 'string',
            'description': '临时文件区里一页 HTML，当这封信的富文本版；留空就按正文自动排一版',
          },
        },
        'required': <String>['body'],
      };

  /// 发出去收不回来：不论审批档位多宽，都先问一句。
  @override
  bool get alwaysAsk => true;

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.write;

  @override
  String summarize(Map<String, Object?> args) {
    final String subject = readString(args, 'subject').trim();
    final String to = readString(args, 'to').trim();
    final String why = readString(args, 'why').trim();
    final String head = '发邮件${subject.isEmpty ? '' : '「$subject」'}'
        '${to.isEmpty ? '（默认收件人）' : '给 $to'}';
    return why.isEmpty ? head : '$head · $why';
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
    // 模型选的那个收件人必须在设置允许的名单里，不是它自己说了算。
    final String wanted = readString(args, 'to').trim();
    if (wanted.isNotEmpty && !mail.value.canSendTo(wanted)) {
      final List<String> allowed = mail.value.allowed;
      return ToolOutcome.failure(allowed.isEmpty
          ? '设置里还没写允许发给谁，只能发给默认收件人。'
          : '$wanted 不在允许发送的名单里。能发的是：${allowed.join('、')}。');
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
        await mailer.send(subject, mailBody(line: body, detail: ''), html: html, to: wanted);
    if (!result.ok) return ToolOutcome.failure('邮件没发出去：${result.error}');
    final String who = wanted.isEmpty ? mail.value.recipients.join('、') : wanted;
    final String why = readString(args, 'why').trim();
    return ToolOutcome.success(
        stdout: '发出去了：$subject → $who${why.isEmpty ? '' : '（$why）'}');
  }
}
