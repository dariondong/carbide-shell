import 'dart:convert';
import 'dart:io';

import '../core/mail_html.dart';
import '../core/smtp.dart';
import 'secrets.dart';

export '../core/mail_html.dart';

/// 邮件通知的设置：一个 JSON 文件，密码单独放安全存储。
class MailStore {
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

  Future<SmtpResult> send(String subject, String body) async {
    final SmtpConfig config = store.value;
    if (!config.ready) {
      return SmtpResult(error: config.missing.isEmpty ? '邮件没配全' : config.missing);
    }
    return sendMail(
      config,
      await store.password(),
      subject: subject,
      body: body,
      html: config.html ? mailHtml(body) : '',
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
