import '../core/deepseek_search.dart';
import '../core/models.dart';
import '../core/tools.dart';
import '../data/secrets.dart';
import '../data/settings.dart';

/// 联网的两件工具：`web_search` 找网页，`web_fetch` 读一页。
///
/// 走的是 DeepSeek 自己的搜索接口，用当前这套配置的密钥，所以只读、不用点批准。
/// 模型地址是代理、那边没有这两条接口时，工具会如实说一句缺什么。
class WebSearchTool extends Tool {
  WebSearchTool({
    required this.settings,
    required this.secrets,
    required this.profileId,
  });

  final SettingsStore settings;
  final SecretStore secrets;

  /// 这场对话钉在哪套配置上：密钥和搜索地址都跟着它。
  final String Function() profileId;

  @override
  String get name => 'web_search';

  @override
  String get description =>
      '联网搜索：给一句话，拿回一批网页（标题、地址、摘要）。'
      '问到新鲜事、价格、版本、新闻、自己不知道的细节时用它，别靠记忆硬答。'
      '要读整页再用 web_fetch。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'query': <String, Object?>{
            'type': 'string',
            'description': '搜什么。支持 site:、-site:、after:、lang: 这些写法',
          },
          'count': <String, Object?>{
            'type': 'integer',
            'description': '要几条，1 到 20，默认 8',
          },
          'content': <String, Object?>{
            'type': 'boolean',
            'description': '要不要顺带把网页正文也取回来，默认不要',
          },
        },
        'required': <String>['query'],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.read;

  @override
  String summarize(Map<String, Object?> args) => '搜「${(args['query'] ?? '').toString().trim()}」';

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String query = '${args['query'] ?? ''}'.trim();
    if (query.isEmpty) return const ToolOutcome.failure('没说要搜什么');
    final int count = args['count'] is num ? (args['count'] as num).toInt() : 8;
    final bool content = args['content'] == true;
    final String key = await _key();
    final DeepSeekSearch client = DeepSeekSearch(baseUrl: _base(), apiKey: key);
    try {
      final List<SearchHit> hits =
          await client.search(query, count: count.clamp(1, 20), content: content);
      if (hits.isEmpty) {
        return ToolOutcome.success(stdout: '「$query」一条也没搜到。换个说法，或者去掉限定词再试。');
      }
      return ToolOutcome.success(stdout: _format(query, hits));
    } on SearchFailure catch (e) {
      return ToolOutcome.failure(e.message);
    }
  }

  /// 标题、地址、摘要一行一条。太长的摘要留前面那截，正文只留一点。
  String _format(String query, List<SearchHit> hits) {
    final StringBuffer out = StringBuffer('「$query」搜到 ${hits.length} 条：\n');
    for (int i = 0; i < hits.length; i += 1) {
      final SearchHit h = hits[i];
      out.writeln('${i + 1}. ${h.title.isEmpty ? h.url : h.title}');
      out.writeln('   ${h.url}');
      final String digest = h.digest;
      if (digest.isNotEmpty) out.writeln('   ${_cut(digest, 400)}');
      final List<String> tail = <String>[
        if (h.site.isNotEmpty) h.site,
        if (h.date.isNotEmpty) h.date.substring(0, h.date.length > 10 ? 10 : h.date.length),
      ];
      if (tail.isNotEmpty) out.writeln('   ${tail.join(' · ')}');
      if (h.content.isNotEmpty) {
        out.writeln('   正文开头：${_cut(h.content, 500)}');
      }
    }
    return _cut(out.toString().trimRight(), 6000);
  }

  static String _cut(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';

  /// 搜索地址跟这场对话钉的那套配置走：那是密钥的主人。
  String _base() =>
      (settings.value.profileById(profileId()) ?? settings.value.active).baseUrl;

  Future<String> _key() async {
    final ModelProfile profile =
        settings.value.profileById(profileId()) ?? settings.value.active;
    final String key = await secrets.read(modelSecretKeyFor(profile.id));
    if (key.isNotEmpty) return key;
    return secrets.read(modelSecretKey());
  }
}

/// `web_fetch`：把一个地址读成 Markdown。
class WebFetchTool extends Tool {
  WebFetchTool({required this.settings, required this.secrets, required this.profileId});

  final SettingsStore settings;
  final SecretStore secrets;
  final String Function() profileId;

  @override
  String get name => 'web_fetch';

  @override
  String get description => '打开一个网页，把正文取回来（Markdown）。搜索到想细看的地址再调它，一次一个。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'url': <String, Object?>{'type': 'string', 'description': 'http 或 https 的完整地址'},
        },
        'required': <String>['url'],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.read;

  @override
  String summarize(Map<String, Object?> args) => '读 ${(args['url'] ?? '').toString()}';

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String url = '${args['url'] ?? ''}'.trim();
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
      return const ToolOutcome.failure('要一个 http 或 https 的完整地址');
    }
    final ModelProfile profile =
        settings.value.profileById(profileId()) ?? settings.value.active;
    final DeepSeekSearch client = DeepSeekSearch(baseUrl: profile.baseUrl, apiKey: await _key());
    try {
      final SearchPage page = await client.fetch(url);
      final String body =
          page.content.length <= 8000 ? page.content : '${page.content.substring(0, 8000)}\n…（后面还有，没铺开）';
      return ToolOutcome.success(
        stdout: '${page.title.isEmpty ? url : page.title}\n$url\n\n$body',
      );
    } on SearchFailure catch (e) {
      return ToolOutcome.failure(e.message);
    }
  }

  Future<String> _key() async {
    final ModelProfile profile =
        settings.value.profileById(profileId()) ?? settings.value.active;
    final String key = await secrets.read(modelSecretKeyFor(profile.id));
    if (key.isNotEmpty) return key;
    return secrets.read(modelSecretKey());
  }
}
