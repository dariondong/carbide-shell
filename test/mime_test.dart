import 'dart:convert';

import 'package:carbide_shell/core/mime.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一封信在到达这里之前是字节。测试里也要按字节造：先 UTF-8 编，再按 latin1 摊成字符。
String bytes(String text) => latin1.decode(utf8.encode(text));

/// 把一个字符串编成 quoted-printable 正文（每个字节一个 =XX）。
String qpT(String text) => utf8
    .encode(text)
    .map((int b) => '=${b.toRadixString(16).toUpperCase().padLeft(2, '0')}')
    .join();

void main() {
  test('头部折行接回去，=?UTF-8?B?…?= 解开', () {
    final String raw = 'From: =?UTF-8?B?${base64.encode(utf8.encode('张三'))}?= '
        '<zhangsan@example.com>\r\n'
        'Subject: =?UTF-8?B?${base64.encode(utf8.encode('你好'))}?= 后面还有字\r\n'
        'X-Long: 第一段\r\n'
        '  第二段\r\n'
        '\r\n'
        '正文';
    final ParsedMail mail = parseMail(bytes(raw));
    expect(mail.subject, '你好 后面还有字');
    expect(mail.from, contains('张三'));
    expect(mail.headers['x-long'], '第一段 第二段');
  });

  test('multipart/alternative 取纯文本那一段', () {
    final String raw = 'From: a@b.com\r\n'
        'Subject: 两段\r\n'
        'Content-Type: multipart/alternative; boundary="mix"\r\n'
        '\r\n'
        '这条不是正文\r\n'
        '--mix\r\n'
        'Content-Type: text/plain; charset=utf-8\r\n'
        'Content-Transfer-Encoding: base64\r\n'
        '\r\n'
        '${base64.encode(utf8.encode('纯文本这一份'))}\r\n'
        '--mix\r\n'
        'Content-Type: text/html; charset=utf-8\r\n'
        '\r\n'
        '<p>HTML 那一份</p>\r\n'
        '--mix--\r\n';
    final ParsedMail mail = parseMail(bytes(raw));
    expect(mail.text.trim(), '纯文本这一份');
    expect(mail.html, contains('HTML 那一份'));
    expect(mail.readable, '纯文本这一份');
  });

  test('只有 HTML 的时候把标签去掉当正文', () {
    final String raw = 'Subject: 只有网页\r\n'
        'Content-Type: text/html; charset=utf-8\r\n'
        '\r\n'
        '<div>第一行</div><div>第二行&nbsp;&amp;&nbsp;第三行</div>';
    final ParsedMail mail = parseMail(bytes(raw));
    expect(mail.text, '');
    expect(mail.readable, '第一行\n第二行 & 第三行');
  });

  test('quoted-printable 的软换行和 =XX 都还原', () {
    final String raw = 'Content-Type: text/plain; charset=utf-8\r\n'
        'Content-Transfer-Encoding: quoted-printable\r\n'
        '\r\n'
        '${qpT('中文')} ${qpT('这一行很长')}\r\n'
        '${qpT('接着写')}=0A${qpT('下一行')}=\r\n';
    final ParsedMail mail = parseMail(raw);
    expect(mail.text.trim(), '中文 这一行很长\n接着写\n下一行');
  });

  test('附件只数个数，不当正文', () {
    final String raw = 'Subject: 带附件\r\n'
        'Content-Type: multipart/mixed; boundary="m"\r\n'
        '\r\n'
        '--m\r\n'
        'Content-Type: text/plain; charset=utf-8\r\n'
        '\r\n'
        '正文在这\r\n'
        '--m\r\n'
        'Content-Type: application/pdf; name="a.pdf"\r\n'
        'Content-Disposition: attachment; filename="a.pdf"\r\n'
        'Content-Transfer-Encoding: base64\r\n'
        '\r\n'
        'JVBERi0xLjQK\r\n'
        '--m--\r\n';
    final ParsedMail mail = parseMail(bytes(raw));
    expect(mail.attachments, 1);
    expect(mail.readable, '正文在这');
  });

  test('Head 里夹着原始 8 位字节的主题也认', () {
    final String raw = 'Subject: ${latin1.decode(utf8.encode('未编码的中文'))}\r\n\r\n正文';
    expect(parseMail(bytes(raw)).subject, '未编码的中文');
  });

  test('headToText 不把 script 和注释当成正文', () {
    expect(htmlToText('<style>.a{}</style><!-- 别让人看见 --><p>正文</p>'), '正文');
    expect(unescapeHtml('&#39;&#x4e2d;&lt;'), "'中<");
  });
}
