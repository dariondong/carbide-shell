import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// DeepSeek 的搜索与取网页接口。
///
/// 它家的模型本身不带联网，联网是这两条独立接口：
/// `POST /v1/tools/search`（给一句话，回一批网页）和 `POST /v1/tools/fetch`
/// （给一个地址，回整页 Markdown）。两条都用同一个密钥，按次计费。
class SearchHit {
  const SearchHit({
    required this.title,
    required this.url,
    this.snippet = '',
    this.summary = '',
    this.content = '',
    this.site = '',
    this.date = '',
    this.authority = -1,
  });

  final String title;
  final String url;

  /// 一两句话的摘要，给界面看的那种。
  final String snippet;

  /// 长一点的摘要，几百字，给模型读。
  final String summary;

  /// 网页正文。请求里要了才有。
  final String content;

  final String site;
  final String date;
  final int authority;

  /// 给模型看的那一句：长摘要优先，没有就用短摘要。
  String get digest => summary.trim().isNotEmpty ? summary.trim() : snippet.trim();
}

/// 取回来的那一页。
class SearchPage {
  const SearchPage({required this.title, required this.content});

  final String title;
  final String content;
}

class SearchFailure implements Exception {
  const SearchFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 两条接口的客户端。域名跟模型地址走：直连 DeepSeek 时就是 api.deepseek.com。
class DeepSeekSearch {
  DeepSeekSearch({
    required String baseUrl,
    required this.apiKey,
    this.timeout = const Duration(seconds: 20),
  }) : baseUrl = baseUrl;

  final String baseUrl;
  final String apiKey;
  final Duration timeout;

  Future<List<SearchHit>> search(
    String query, {
    int count = 8,
    bool content = false,
  }) async {
    final String body = await _post('/tools/search', <String, Object?>{
      'query': query,
      'count': count.clamp(1, 50),
      'need_content': content,
    });
    return parseSearch(body);
  }

  Future<SearchPage> fetch(String url) async {
    final String body = await _post('/tools/fetch', <String, Object?>{'url': url});
    return parsePage(body);
  }

  /// 地址怎么拼：用户填的地址常带 `/v1`，别再叠一层。
  static String endpoint(String baseUrl, String path) {
    String base = baseUrl.trim();
    if (base.isEmpty) base = 'https://api.deepseek.com';
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (base.endsWith('/v1')) base = base.substring(0, base.length - 3);
    return '$base/v1$path';
  }

  /// 搜索接口的回话。认不出来的、空的都当没有结果。
  static List<SearchHit> parseSearch(String body) {
    final Object? decoded = _decode(body);
    if (decoded is! Map) return const <SearchHit>[];
    final Object? list = decoded['results'];
    if (list is! List) return const <SearchHit>[];
    final List<SearchHit> out = <SearchHit>[];
    for (final Object? raw in list) {
      if (raw is! Map) continue;
      final String url = '${raw['url'] ?? ''}'.trim();
      if (url.isEmpty) continue;
      out.add(SearchHit(
        title: '${raw['title'] ?? ''}'.trim(),
        url: url,
        snippet: '${raw['snippet'] ?? ''}'.trim(),
        summary: '${raw['summary'] ?? ''}'.trim(),
        content: '${raw['content'] ?? ''}'.trim(),
        site: '${raw['site_name'] ?? ''}'.trim(),
        date: '${raw['date'] ?? ''}'.trim(),
        authority: raw['authority'] is num ? (raw['authority'] as num).toInt() : -1,
      ));
    }
    return out;
  }

  static SearchPage parsePage(String body) {
    final Object? decoded = _decode(body);
    if (decoded is! Map) {
      throw const SearchFailure('取回来的不是一页网页');
    }
    final String content = '${decoded['content'] ?? ''}'.trim();
    if (content.isEmpty) {
      throw const SearchFailure('那一页没有可读的正文');
    }
    return SearchPage(title: '${decoded['title'] ?? ''}'.trim(), content: content);
  }

  static Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  Future<String> _post(String path, Map<String, Object?> payload) async {
    if (apiKey.trim().isEmpty) {
      throw const SearchFailure('这套配置没有密钥，搜索发不出去');
    }
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final HttpClientRequest request =
          await client.postUrl(Uri.parse(endpoint(baseUrl, path)));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${apiKey.trim()}');
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));
      final HttpClientResponse response = await request.close().timeout(timeout);
      final String body = await response.transform(utf8.decoder).join().timeout(timeout);
      if (response.statusCode != 200) {
        throw SearchFailure(_reason(response.statusCode, body));
      }
      return body;
    } on SearchFailure {
      rethrow;
    } on TimeoutException {
      throw const SearchFailure('搜索没等到回话（超时）');
    } on SocketException catch (e) {
      throw SearchFailure('连不上搜索地址：${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  /// 状态码翻成人话。4xx 都是「别原样再试」，5xx 和 429 可以等一会儿。
  static String _reason(int code, String body) {
    String detail = '';
    final Object? decoded = _decode(body);
    if (decoded is Map) {
      final Object? error = decoded['error'];
      if (error is Map) detail = '${error['message'] ?? ''}'.trim();
    }
    final String extra = detail.isEmpty ? '' : '：$detail';
    return switch (code) {
      400 => '请求写得不对$extra',
      401 => '密钥不对或者过期了$extra',
      402 => '账户余额不够，搜索按次计费$extra',
      403 => '这条请求被挡下了$extra',
      404 => '这个地址上没有搜索接口（HTTP 404）。'
          '它只挂在 DeepSeek 自己的地址上，代理地址一般没有；把模型地址换成 api.deepseek.com 那种直连的再试',
      408 => '搜索那边读请求超时，等一会儿再来',
      413 => '请求太大了',
      429 => '搜索次数太快（每分钟有上限），等一会儿再来',
      500 => '搜索服务那边出错了，等一会儿再来',
      504 => '搜索那边超时了，等一会儿再来',
      _ => '搜索失败（HTTP $code）$extra',
    };
  }
}
