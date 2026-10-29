import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:carbide_shell/core/imap.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一台最小的 IMAP 服务器：只认这几条命令，够把一个会话走完。
class FakeImap {
  FakeImap({this.badLogin = false});

  final bool badLogin;
  late ServerSocket _server;
  final List<String> commands = <String>[];

  static const String header5 = 'From: =?UTF-8?B?5byg5LiJ?= <zhangsan@example.com>\r\n'
      'Subject: =?UTF-8?B?5L2g5aW9?=\r\n'
      'Date: Thu, 29 Oct 2026 16:39:00 +0800\r\n'
      '\r\n';

  static const String header6 = 'From: lisi@example.com\r\n'
      'Subject: second\r\n'
      'Date: Thu, 29 Oct 2026 17:02:00 +0800\r\n'
      '\r\n';

  static String get full5 => 'From: =?UTF-8?B?5byg5LiJ?= <zhangsan@example.com>\r\n'
      'Subject: =?UTF-8?B?5L2g5aW9?=\r\n'
      'Date: Thu, 29 Oct 2026 16:39:00 +0800\r\n'
      'Content-Type: multipart/alternative; boundary="b1"\r\n'
      '\r\n'
      '--b1\r\n'
      'Content-Type: text/plain; charset=utf-8\r\n'
      'Content-Transfer-Encoding: base64\r\n'
      '\r\n'
      '${base64.encode(utf8.encode('你好，这是正文\n'))}\r\n'
      '--b1\r\n'
      'Content-Type: text/html; charset=utf-8\r\n'
      '\r\n'
      '<p>html</p>\r\n'
      '--b1--\r\n';

  Future<int> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((Socket socket) {
      unawaited(_serve(socket));
    });
    return _server.port;
  }

  Future<void> stop() => _server.close();

  Future<void> _serve(Socket socket) async {
    socket.write('* OK [CAPABILITY IMAP4rev1] fake ready\r\n');
    await socket.flush();
    final Stream<String> lines =
        socket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter());
    await for (final String line in lines) {
      if (line.trim().isEmpty) continue;
      commands.add(line);
      final String tag = line.split(' ').first;
      final String rest = line.length > tag.length ? line.substring(tag.length + 1) : '';
      final String upper = rest.toUpperCase();
      if (upper.startsWith('LOGIN')) {
        socket.write(badLogin
            ? '$tag NO [AUTHENTICATIONFAILED] 账号或密码不对\r\n'
            : '$tag OK LOGIN completed\r\n');
      } else if (upper.startsWith('SELECT')) {
        socket.write('* 2 EXISTS\r\n* FLAGS (\\Seen)\r\n$tag OK [READ-WRITE] done\r\n');
      } else if (upper.startsWith('UID SEARCH')) {
        socket.write('* SEARCH 5 6\r\n$tag OK SEARCH completed\r\n');
      } else if (upper.startsWith('UID FETCH')) {
        if (upper.contains('HEADER.FIELDS')) {
          for (final List<String> one in <List<String>>[
            <String>['5', header5],
            <String>['6', header6],
          ]) {
            socket.write('* 1 FETCH (UID ${one.first} FLAGS () INTERNALDATE '
                '"29-Oct-2026 16:39:00 +0800" RFC822.SIZE ${one.last.length} '
                'BODY[HEADER.FIELDS (FROM SUBJECT DATE)] {${one.last.length}}\r\n');
            socket.write(one.last);
            socket.write(')\r\n');
          }
        } else {
          socket.add(utf8.encode('* 1 FETCH (UID 5 INTERNALDATE '
              '"29-Oct-2026 16:39:00 +0800" BODY[] {${utf8.encode(full5).length}}\r\n'));
          socket.add(utf8.encode(full5));
          socket.write(')\r\n');
        }
        socket.write('$tag OK FETCH completed\r\n');
      } else if (upper.startsWith('LIST')) {
        socket.write('* LIST (\\Noselect) "/" ""\r\n$tag OK LIST completed\r\n');
      } else if (upper.startsWith('LOGOUT')) {
        socket.write('* BYE bye\r\n$tag OK LOGOUT completed\r\n');
      } else {
        socket.write('$tag BAD 不认识这条\r\n');
      }
      await socket.flush();
    }
  }
}

void main() {
  test('没填服务器就不连', () async {
    final ImapClient client = ImapClient(const ImapConfig(), 'pw');
    await expectLater(client.latest(), throwsA(isA<ImapError>()));
  });

  test('列最近几封：主题解开、未读与时间都对', () async {
    final FakeImap fake = FakeImap();
    final int port = await fake.start();
    final ImapClient client = ImapClient(
      ImapConfig(host: '127.0.0.1', port: port, secure: false, user: 'me@example.com'),
      'pw',
    );
    final List<MailSummary> list = await client.latest(count: 5);
    expect(list.length, 2);
    expect(list.first.uid, 5);
    expect(list.first.subject, '你好');
    expect(list.first.fromName, '张三');
    expect(list.first.fromAddress, 'zhangsan@example.com');
    expect(list.first.unread, isTrue);
    expect(list.first.at?.toUtc(), DateTime.utc(2026, 10, 29, 8, 39));
    expect(list.last.unread, isTrue);
    await fake.stop();
  });

  test('LOGIN 被拒时说话清楚', () async {
    final FakeImap fake = FakeImap(badLogin: true);
    final int port = await fake.start();
    final ImapClient client = ImapClient(
      ImapConfig(host: '127.0.0.1', port: port, secure: false, user: 'me@example.com'),
      'wrong',
    );
    await expectLater(
      client.latest(),
      throwsA(predicate((Object? e) => e is ImapError && e.message.contains('账号或密码'))),
    );
    await fake.stop();
  });

  test('看一封：正文挑纯文本那段，HTML 留着不显示', () async {
    final FakeImap fake = FakeImap();
    final int port = await fake.start();
    final ImapClient client = ImapClient(
      ImapConfig(host: '127.0.0.1', port: port, secure: false, user: 'me@example.com'),
      'pw',
    );
    final MailDetail detail = await client.read(5);
    expect(detail.head.subject, '你好');
    expect(detail.body, contains('你好，这是正文'));
    expect(detail.html, contains('<p>html</p>'));
    expect(detail.attachments, 0);
    await fake.stop();
  });

  test('服务器日期写成 29-Oct-2026 这种也认', () {
    expect(serverDate('29-Oct-2026 16:39:00 +0800')?.toUtc(),
        DateTime.utc(2026, 10, 29, 8, 39));
    expect(serverDate('01-Jan-2026 00:05:00 -0500')?.toUtc(),
        DateTime.utc(2026, 1, 1, 5, 5));
    expect(serverDate('乱写的'), isNull);
  });
}
