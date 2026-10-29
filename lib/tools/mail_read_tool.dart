import '../core/models.dart';
import '../core/tools.dart';
import '../data/mail.dart';

/// `mail_inbox`：看收件箱里最近几封，只列头几条，不动正文。
///
/// 读信只是看，不改任何东西，所以不拦；想看全文让模型接着调 `mail_read`。
class MailInboxTool extends Tool {
  MailInboxTool(this.mail);

  final MailStore mail;

  @override
  String get name => 'mail_inbox';

  @override
  String get description =>
      '看用户邮箱的收件箱：最近几封的发件人、主题、时间、读过没有。'
      '只看标题，正文用 mail_read 按 uid 取。没配好 IMAP 会如实回一句。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'count': <String, Object?>{
            'type': 'integer',
            'description': '看最近几封，默认 10，最多 30',
          },
          'unread_only': <String, Object?>{
            'type': 'boolean',
            'description': '只要没读过的',
          },
        },
      };

  @override
  ToolRisk get risk => ToolRisk.read;

  @override
  String summarize(Map<String, Object?> args) =>
      '看一眼收件箱${_unreadOnly(args) ? '（只看没读的）' : ''}';

  static bool _unreadOnly(Map<String, Object?> args) => args['unread_only'] == true;

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    if (!mail.inboxReady) {
      return ToolOutcome.failure(
          '读不了邮箱：${mail.value.imapMissing.isEmpty ? '设置里没填 IMAP 服务器' : mail.value.imapMissing}。'
          '让人去设置 → 邮件里把「收信 IMAP 服务器」填上，或者把话写在回答里。');
    }
    int count = readInt(args, 'count', fallback: 10);
    if (count < 1) count = 1;
    if (count > 30) count = 30;
    try {
      final List<MailSummary> list =
          await mail.inbox(count: count, unreadOnly: _unreadOnly(args));
      if (list.isEmpty) {
        return ToolOutcome.success(
            stdout: _unreadOnly(args) ? '收件箱里没有没读过的信。' : '收件箱是空的。');
      }
      final StringBuffer b = StringBuffer()
        ..writeln('最近 ${list.length} 封（uid 从旧到新）：');
      for (final MailSummary one in list) {
        b.writeln('- uid ${one.uid} · ${one.when} · ${one.unread ? '未读' : '已读'} · '
            '${_person(one)} · ${one.subject.isEmpty ? '（无主题）' : one.subject}');
      }
      b.write('正文用 mail_read 按 uid 取。');
      return ToolOutcome.success(stdout: b.toString());
    } on ImapError catch (e) {
      return ToolOutcome.failure('收件箱拉不下来：${e.message}');
    } catch (e) {
      return ToolOutcome.failure('收件箱拉不下来：$e');
    }
  }

  static String _person(MailSummary one) {
    final String name = one.fromName;
    final String address = one.fromAddress;
    if (address.isEmpty) return name.isEmpty ? '（不知道谁）' : name;
    if (name.isEmpty || name == address) return address;
    return '$name <$address>';
  }
}

/// `mail_read`：读某一封的正文。
class MailReadTool extends Tool {
  MailReadTool(this.mail, {this.maxChars = 4000});

  final MailStore mail;

  /// 正文最多给模型这么多字，再长就截。
  final int maxChars;

  @override
  String get name => 'mail_read';

  @override
  String get description =>
      '读收件箱里某一封的正文，uid 从 mail_inbox 的列表里拿。'
      '附件只数个数，不下载。太长的正文会截断。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'uid': <String, Object?>{
            'type': 'integer',
            'description': 'mail_inbox 列出来的那个 uid',
          },
        },
        'required': <String>['uid'],
      };

  @override
  ToolRisk get risk => ToolRisk.read;

  @override
  String summarize(Map<String, Object?> args) => '读邮件 uid ${readInt(args, 'uid')}';

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final int uid = readInt(args, 'uid');
    if (uid <= 0) {
      return const ToolOutcome.failure('uid 没给。先用 mail_inbox 看一眼列表，再把那个 uid 写上。');
    }
    try {
      final MailDetail one = await mail.read(uid);
      final StringBuffer b = StringBuffer()
        ..writeln('uid $uid · ${one.head.when}')
        ..writeln('发件人：${one.head.from.isEmpty ? '（没有）' : one.head.from}')
        ..writeln('主题：${one.head.subject.isEmpty ? '（无主题）' : one.head.subject}');
      if (one.attachments > 0) b.writeln('附件：${one.attachments} 个（没取）');
      final String body = one.body.trim();
      if (body.isEmpty) {
        b.writeln('（这封信没有能读的正文）');
      } else {
        b
          ..writeln()
          ..write(body.length > maxChars ? '${body.substring(0, maxChars)}…' : body);
      }
      return ToolOutcome.success(stdout: b.toString());
    } on ImapError catch (e) {
      return ToolOutcome.failure('这封信读不出来：${e.message}');
    } catch (e) {
      return ToolOutcome.failure('这封信读不出来：$e');
    }
  }
}
