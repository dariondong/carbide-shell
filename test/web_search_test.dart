import 'dart:convert';

import 'package:carbide_shell/core/deepseek_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('搜索地址怎么拼', () {
    test('直连地址加 /v1/tools/...', () {
      expect(DeepSeekSearch.endpoint('https://api.deepseek.com', '/tools/search'),
          'https://api.deepseek.com/v1/tools/search');
    });

    test('已经带 /v1 的不再叠一层', () {
      expect(DeepSeekSearch.endpoint('https://api.deepseek.com/v1', '/tools/fetch'),
          'https://api.deepseek.com/v1/tools/fetch');
    });

    test('末尾斜杠和空格都不碍事', () {
      expect(DeepSeekSearch.endpoint('  https://api.deepseek.com// ', '/tools/search'),
          'https://api.deepseek.com/v1/tools/search');
    });

    test('地址空着就用官方那个', () {
      expect(DeepSeekSearch.endpoint('', '/tools/search'),
          'https://api.deepseek.com/v1/tools/search');
    });
  });

  group('搜索回话怎么读', () {
    test('按文档那几条读出来', () {
      final String body = jsonEncode(<String, Object?>{
        'results': <Object?>[
          <String, Object?>{
            'title': 'DeepSeek V4 发布',
            'url': 'https://example.com/a',
            'snippet': '短摘要',
            'summary': '长摘要',
            'content': '',
            'site_name': 'Example',
            'date': '2026-06-01T00:00:00+00:00',
            'authority': 3,
          },
        ],
      });
      final List<SearchHit> hits = DeepSeekSearch.parseSearch(body);
      expect(hits.length, 1);
      expect(hits.first.title, 'DeepSeek V4 发布');
      expect(hits.first.url, 'https://example.com/a');
      expect(hits.first.digest, '长摘要');
      expect(hits.first.site, 'Example');
      expect(hits.first.authority, 3);
    });

    test('没有长摘要就用短摘要', () {
      final String body = jsonEncode(<String, Object?>{
        'results': <Object?>[
          <String, Object?>{'title': 'x', 'url': 'https://example.com/x', 'snippet': '短的'},
        ],
      });
      expect(DeepSeekSearch.parseSearch(body).single.digest, '短的');
    });

    test('没有结果的空数组不算错', () {
      expect(DeepSeekSearch.parseSearch('{"results":[]}'), isEmpty);
    });

    test('缺地址的那条丢掉，别拿半条去糊模型', () {
      final String body = jsonEncode(<String, Object?>{
        'results': <Object?>[
          <String, Object?>{'title': '没有地址'},
          <String, Object?>{'title': '有地址', 'url': 'https://example.com/y'},
        ],
      });
      expect(DeepSeekSearch.parseSearch(body).single.url, 'https://example.com/y');
    });

    test('不是 JSON 就当没有结果', () {
      expect(DeepSeekSearch.parseSearch('<html>502</html>'), isEmpty);
    });
  });

  group('取回来的一页', () {
    test('标题和正文都读出来', () {
      final SearchPage page = DeepSeekSearch.parsePage(
        jsonEncode(<String, Object?>{'title': '示例', 'content': '# 示例\n\n正文'}),
      );
      expect(page.title, '示例');
      expect(page.content, '# 示例\n\n正文');
    });

    test('正文空着要报出来，不能当成功', () {
      expect(
        () => DeepSeekSearch.parsePage(jsonEncode(<String, Object?>{'title': 'x', 'content': ''})),
        throwsA(isA<SearchFailure>()),
      );
    });

    test('回的不是 JSON 也报出来', () {
      expect(() => DeepSeekSearch.parsePage('oops'), throwsA(isA<SearchFailure>()));
    });
  });
}
