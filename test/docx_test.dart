import 'dart:convert';
import 'dart:io';

import 'package:carbide_shell/core/docx.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一段最小可用的 document.xml。
String _doc(String body) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
    '<w:body>$body</w:body></w:document>';

String _para(String text) => '<w:p><w:r><w:t>$text</w:t></w:r></w:p>';

void main() {
  test('真的一份 .docx 读出正文', () {
    final String? text =
        docxText(File('test/fixtures/sample.docx').readAsBytesSync());
    expect(text, isNotNull);
    expect(
      text,
      equals('第一段：装上之后能干什么。\n'
          '第二段 & 一行里带制表符\t和软换行\n下一行\n'
          '\n'
          '第三段：<标签> 与数字实体 中\n'
          '末尾一句。'),
    );
  });

  test('页码这类域代码不进正文', () {
    final String? text = docxText(_zip(<String, String>{
      'word/document.xml': _doc(
        '<w:p><w:r><w:instrText> PAGE \\* MERGEFORMAT </w:instrText></w:r>'
        '<w:r><w:t>只有这句。</w:t></w:r></w:p>',
      ),
    }));
    expect(text, '只有这句。');
  });

  test('同一段被拆成几段字也拼得起来', () {
    final String? text = docxText(_zip(<String, String>{
      'word/document.xml': _doc(
        '<w:p><w:r><w:t>装上之</w:t></w:r><w:r><w:t>后能干</w:t></w:r>'
        '<w:r><w:t>什么。</w:t></w:r></w:p>',
      ),
    }));
    expect(text, '装上之后能干什么。');
  });

  test('写了数据描述符、本地头里长度空着的包也读得出', () {
    expect(
      docxText(_zip(<String, String>{
        'word/document.xml': _doc(_para('描述符写法')),
      }, descriptor: true)),
      '描述符写法',
    );
  });

  test('东西压着没解（method 0）也读得出', () {
    final String? text = docxText(_zip(<String, String>{
      'word/document.xml': _doc(_para('存着的')),
    }, deflate: false));
    expect(text, '存着的');
  });

  test('压缩的包也读得出', () {
    final String? text = docxText(_zip(<String, String>{
      'word/document.xml': _doc(_para('压着的一句')),
    }));
    expect(text, '压着的一句');
  });

  test('不是 zip 就返回 null，不拿半截东西冒充', () {
    expect(docxText(utf8.encode('这不是一个包，只是一段话')), isNull);
    expect(docxText(utf8.encode('PK\u0003\u0004 半截头')), isNull);
    expect(docxText(<int>[]), isNull);
  });

  test('压缩包里没有正文就返回 null', () {
    expect(
      docxText(_zip(<String, String>{
        'word/styles.xml': '<w:styles/>',
      })),
      isNull,
    );
  });

  test('只有标签没有字也返回 null', () {
    expect(
      docxText(_zip(<String, String>{'word/document.xml': _doc('')})),
      isNull,
    );
  });

  test('&amp; 不会被当成标签的尖括号', () {
    final String? text = docxText(_zip(<String, String>{
      'word/document.xml': _doc(_para('a &amp;lt; b')),
    }));
    expect(text, 'a &lt; b');
  });

  test('数字实体认十进制与十六进制', () {
    final String? text = docxText(_zip(<String, String>{
      'word/document.xml': _doc(_para('&#20013; &#x56FD;')),
    }));
    expect(text, '中 国');
  });
}

// ---- 造包：够 docxText 读就行，CRC 写 0（读的那边不看它） ----

List<int> _u16(int v) => <int>[v & 0xFF, (v >> 8) & 0xFF];

List<int> _u32(int v) =>
    <int>[v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

List<int> _zip(Map<String, String> files, {bool deflate = true, bool descriptor = false}) {
  final List<int> body = <int>[];
  final List<int> dir = <int>[];
  files.forEach((String name, String content) {
    final List<int> raw = utf8.encode(content);
    final int method = deflate ? 8 : 0;
    final List<int> packed = deflate ? ZLibEncoder(raw: true).convert(raw) : raw;
    final List<int> nameBytes = utf8.encode(name);
    final int offset = body.length;
    body
      ..addAll(<int>[0x50, 0x4B, 0x03, 0x04])
      ..addAll(_u16(20))
      ..addAll(_u16(descriptor ? 8 : 0))
      ..addAll(_u16(method))
      ..addAll(_u16(0))
      ..addAll(_u16(0))
      ..addAll(_u32(0))
      // 写了数据描述符的条目，本地头里的长度是 0，真正的长度只在中央目录里
      ..addAll(_u32(descriptor ? 0 : packed.length))
      ..addAll(_u32(descriptor ? 0 : raw.length))
      ..addAll(_u16(nameBytes.length))
      ..addAll(_u16(0))
      ..addAll(nameBytes)
      ..addAll(packed);
    if (descriptor) {
      body
        ..addAll(<int>[0x50, 0x4B, 0x07, 0x08])
        ..addAll(_u32(0))
        ..addAll(_u32(packed.length))
        ..addAll(_u32(raw.length));
    }
    dir
      ..addAll(<int>[0x50, 0x4B, 0x01, 0x02])
      ..addAll(_u16(20))
      ..addAll(_u16(20))
      ..addAll(_u16(0))
      ..addAll(_u16(method))
      ..addAll(_u16(0))
      ..addAll(_u16(0))
      ..addAll(_u32(0))
      ..addAll(_u32(packed.length))
      ..addAll(_u32(raw.length))
      ..addAll(_u16(nameBytes.length))
      ..addAll(_u16(0))
      ..addAll(_u16(0))
      ..addAll(_u16(0))
      ..addAll(_u16(0))
      ..addAll(_u32(0))
      ..addAll(_u32(offset))
      ..addAll(nameBytes);
  });
  final List<int> out = <int>[...body, ...dir];
  out
    ..addAll(<int>[0x50, 0x4B, 0x05, 0x06])
    ..addAll(_u16(0))
    ..addAll(_u16(0))
    ..addAll(_u16(files.length))
    ..addAll(_u16(files.length))
    ..addAll(_u32(dir.length))
    ..addAll(_u32(body.length))
    ..addAll(_u16(0));
  return out;
}
