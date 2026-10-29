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

/// GBK 的字节：「测试邮件」「张三」「今天天气很好。」
const List<int> gbkTitle = <int>[0xb2, 0xe2, 0xca, 0xd4, 0xd3, 0xca, 0xbc, 0xfe];
const List<int> gbkName = <int>[0xd5, 0xc5, 0xc8, 0xfd];
const List<int> gbkBody = <int>[
  0xbd, 0xf1, 0xcc, 0xec, 0xcc, 0xec, 0xc6, 0xf8, 0xba, 0xdc, 0xba, 0xc3, 0xa1, 0xa3,
];

/// 一段 GBK 字节按 latin1 摊成字符：读 socket 时就是这么落下来的。
String gbk(List<int> bytes) => latin1.decode(bytes);

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
    expect(parseMail(raw).subject, '未编码的中文');
  });

  test('headToText 不把 script 和注释当成正文', () {
    expect(htmlToText('<style>.a{}</style><!-- 别让人看见 --><p>正文</p>'), '正文');
    expect(unescapeHtml('&#39;&#x4e2d;&lt;'), "'中<");
  });

  // 中文的旧信多数不是 UTF-8：以前一律按 UTF-8 解，满屏是替换符。
  test('GBK 的主题、发件人、正文都解得回来', () {
    final String raw = 'From: =?GBK?B?${base64.encode(gbkName)}?= <zs@example.com>\r\n'
        'Subject: =?gb2312?B?${base64.encode(gbkTitle)}?=\r\n'
        'Content-Type: text/plain; charset=gb2312\r\n'
        'Content-Transfer-Encoding: base64\r\n'
        '\r\n'
        '${base64.encode(gbkBody)}\r\n';
    final ParsedMail mail = parseMail(gbk(utf8.encode(raw)));
    expect(mail.from, '张三 <zs@example.com>');
    expect(mail.subject, '测试邮件');
    expect(mail.readable, '今天天气很好。');
  });

  test('GBK 的 Q 编码与 gb18030 写法', () {
    final String q = gbkTitle
        .map((int b) => '=${b.toRadixString(16).toUpperCase().padLeft(2, '0')}')
        .join();
    expect(decodeWord('=?GBK?Q?$q?='), '测试邮件');
    expect(decodeWord('=?gb18030?B?${base64.encode(gbkTitle)}?='), '测试邮件');
  });

  test('没写 charset 的 GBK 正文也能读', () {
    final List<int> raw = <int>[
      ...utf8.encode('Subject: no-charset\r\nContent-Type: text/plain\r\n\r\n'),
      ...gbkBody,
      ...utf8.encode('\r\n'),
    ];
    expect(parseMail(gbk(raw)).readable, '今天天气很好。');
  });

  test('头部里裸的 GBK 字节也认', () {
    final List<int> raw = <int>[
      ...utf8.encode('Subject: '),
      ...gbkTitle,
      ...utf8.encode('\r\nContent-Type: text/plain\r\n\r\nhi\r\n'),
    ];
    expect(parseMail(gbk(raw)).subject, '测试邮件');
  });

  test('GBK 正文用 quoted-printable 写也一样', () {
    final String q = gbkBody
        .map((int b) => '=${b.toRadixString(16).toUpperCase().padLeft(2, '0')}')
        .join();
    final String raw = 'Content-Type: text/plain; charset="GBK"\r\n'
        'Content-Transfer-Encoding: quoted-printable\r\n'
        '\r\n'
        '$q\r\n';
    expect(parseMail(raw).readable, '今天天气很好。');
  });

  test('UTF-8 的信不被 GBK 抢走', () {
    final String raw = 'Content-Type: text/plain; charset=utf-8\r\n'
        '\r\n'
        '中文正文\r\n';
    expect(parseMail(bytes(raw)).readable, '中文正文');
    expect(isGbkCharset('GB2312'), isTrue);
    expect(isGbkCharset('utf-8'), isFalse);
  });
}
