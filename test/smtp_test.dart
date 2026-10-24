import 'dart:convert';

import 'package:carbide_shell/core/smtp.dart';
import 'package:carbide_shell/data/mail.dart';
import 'package:flutter_test/flutter_test.dart';

const SmtpConfig _config = SmtpConfig(
  enabled: true,
  host: 'smtp.example.com',
  port: 465,
  user: 'someone@example.com',
  from: 'someone@example.com',
  to: 'a@example.com, b@example.com',
);

void main() {
  group('邮件设置', () {
    test('配全了才算 ready', () {
      expect(_config.ready, isTrue);
      expect(_config.recipients, <String>['a@example.com', 'b@example.com']);
    });

    test('差哪一项说得出来', () {
      expect(const SmtpConfig(host: 'h', from: 'x@y', to: 'a@b').missing, '没打开');
      expect(
          const SmtpConfig(enabled: true, from: 'x@y', to: 'a@b').missing, '没填服务器');
      expect(
          const SmtpConfig(enabled: true, host: 'h', from: 'nope', to: 'a@b').missing,
          '没填发件人');
      expect(
          const SmtpConfig(enabled: true, host: 'h', from: 'x@y').missing, '没填收件人');
    });

    test('存下来读回来一样', () {
      final SmtpConfig back = SmtpConfig.fromJson(_config.toJson());
      expect(back.host, 'smtp.example.com');
      expect(back.port, 465);
      expect(back.secure, isTrue);
      expect(back.to, 'a@example.com, b@example.com');
    });

    test('收件人里的空格和分号都当分隔', () {
      const SmtpConfig c = SmtpConfig(
          enabled: true, host: 'h', from: 'x@y', to: ' a@b.c ; d@e.f\n g@h.i ');
      expect(c.recipients, <String>['a@b.c', 'd@e.f', 'g@h.i']);
    });
  });

  group('信的内容', () {
    test('中文主题走 RFC 2047', () {
      final String message = composeMessage(_config, '磁盘 > 90 了', '正文');
      expect(message.contains('Subject: =?UTF-8?B?'), isTrue);
      expect(message.contains('Content-Transfer-Encoding: base64'), isTrue);
      expect(message.endsWith('.\r\n'), isTrue);
    });

    test('纯 ASCII 主题原样写', () {
      final String message = composeMessage(_config, 'disk > 90', 'body');
      expect(message.contains('Subject: disk > 90'), isTrue);
    });

    test('正文按 base64 折行，解码回来一字不差', () {
      const String body = '结论：磁盘 92%，已经清过。\n第二行带一个点 .\n第三行';
      final String message = composeMessage(_config, '跑完了', body);
      final int start = message.indexOf('\r\n\r\n') + 4;
      final String payload = message.substring(start, message.length - 3);
      expect(utf8.decode(base64.decode(payload.replaceAll('\r\n', ''))), body);
      expect(payload.split('\r\n').every((String line) => line.length <= 76), isTrue);
    });

    test('头里有发件人和收件人', () {
      final String message = composeMessage(_config, 's', 'b');
      expect(message.contains('From: <someone@example.com>'), isTrue);
      expect(message.contains('To: <a@example.com>, <b@example.com>'), isTrue);
      expect(message.contains('Date: '), isTrue);
    });
  });

  group('通知正文', () {
    test('结论在前，带上机器和时间', () {
      final String text = mailBody(line: '磁盘体检 · 跑完了', detail: '磁盘 92%');
      expect(text.startsWith('磁盘体检 · 跑完了'), isTrue);
      expect(text.contains('机器：'), isTrue);
      expect(text.contains('时间：'), isTrue);
      expect(text.endsWith('磁盘 92%'), isTrue);
    });

    test('细节太长就截', () {
      final String text = mailBody(line: 'x', detail: 'a' * 50, maxDetail: 10);
      expect(text.contains('aaaaaaaaaa…'), isTrue);
    });
  });
}
