import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/mail_html.dart';
import '../core/smtp.dart';
import 'secrets.dart';

export '../core/mail_html.dart';

/// 邮件通知的设置：一个 JSON 文件，密码单独放安全存储。
///
/// 存一次就通知一声，因为「AI 能发给谁」那份名单模型也能改：设置页开着的时候
/// 它在后台加了一个地址，界面得跟着刷新，否则下一次落盘又会把旧的名单写回去。
class MailStore extends ChangeNotifier {
  MailStore(this.file, this.secrets);

  final File file;
  final SecretStore secrets;
  SmtpConfig value = const SmtpConfig();

  /// 密码存在这里，不进那个 JSON。
  static const String passwordKey = 'mail:password';

  Future<void> load() async {
    if (!file.existsSync()) return;
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        value = SmtpConfig.fromJson(Map<String, Object?>.from(decoded));
      }
    } catch (_) {
      // 文件坏了就当没配过，别拦着应用起不来。
    }
  }

  Future<void> save() async {
    file.parent.createSync(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(value.toJson()));
    notifyListeners();
  }

  /// 换一份「还能发给谁」的名单。加一个、删一个都走这里，写完通知界面重画。
  Future<void> setAllowed(List<String> list) async {
    value = value.copyWith(allowedTo: list);
    await save();
  }

  Future<String> password() => secrets.read(passwordKey);

  Future<void> setPassword(String password) async {
    if (password.isEmpty) {
      await secrets.delete(passwordKey);
      return;
    }
    await secrets.write(passwordKey, password);
  }
}

/// 发通知邮件：设置没开或者没配全就直接不发，不打扰调用方。
class Mailer {
  const Mailer(this.store);

  final MailStore store;

  bool get ready => store.value.ready;

  /// [html] 非空就用它当富文本版（比如一整页排好的报告），空着就按正文自己排。
  /// 设置里把 HTML 版关掉时，两个都不带。
  /// [to] 非空就发给它（模型选的那个），空着就发给设置里的默认收件人。
  Future<SmtpResult> send(String subject, String body,
      {String html = '', String to = ''}) async {
    SmtpConfig config = store.value;
    if (!config.ready) {
      return SmtpResult(error: config.missing.isEmpty ? '邮件没配全' : config.missing);
    }
    if (to.trim().isNotEmpty) {
      if (!config.canSendTo(to)) {
        return SmtpResult(error: '${to.trim()} 不在允许发送的名单里');
      }
      config = config.copyWith(to: to.trim());
    }
    final String supplied = html.trim();
    return sendMail(
      config,
      await store.password(),
      subject: subject,
      body: body,
      html: config.html ? (supplied.isEmpty ? mailHtml(body) : supplied) : '',
    );
  }
}

/// 通知邮件的正文：一句结论在前，细节在后，太长就截。
String mailBody({
  required String line,
  String detail = '',
  int maxDetail = 2000,
}) {
  final StringBuffer b = StringBuffer()
    ..writeln(line)
    ..writeln()
    ..writeln('机器：${Platform.localHostname}')
    ..writeln('时间：${_stamp(DateTime.now())}');
  final String tail = detail.trim();
  if (tail.isNotEmpty) {
    b
      ..writeln()
      ..write(tail.length > maxDetail ? '${tail.substring(0, maxDetail)}…' : tail);
  }
  return b.toString();
}

String _stamp(DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
}
