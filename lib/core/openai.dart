import 'dart:convert';
import 'dart:io';

import 'llm_base.dart';
import 'models.dart';

/// Any service that speaks the OpenAI chat-completions shape.
///
/// The address, the key and the model name are always typed in by the user.
/// Nothing is prefilled, and an empty address refuses to run.
class OpenAiProvider implements LlmProvider {
  OpenAiProvider({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.temperature = 0.2,
    HttpClient? client,
  }) : _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 20);
  }

  final String baseUrl;
  final String apiKey;
  final String model;
  final double temperature;
  final HttpClient _client;

  @override
  String get label => model.isEmpty ? 'unset' : model;

  bool get configured => baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  Uri endpoint() {
    String base = baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (base.endsWith('/chat/completions')) return Uri.parse(base);
    if (base.endsWith('/v1')) return Uri.parse('$base/chat/completions');
    return Uri.parse('$base/v1/chat/completions');
  }

  Map<String, Object?> payload({
    required String system,
    required List<LlmMessage> messages,
    required List<ToolSpec> tools,
  }) {
    final List<Map<String, Object?>> body = <Map<String, Object?>>[
      <String, Object?>{'role': 'system', 'content': system},
    ];
    for (final LlmMessage m in messages) {
      body.add(messageJson(m));
    }
    final Map<String, Object?> out = <String, Object?>{
      'model': model,
      'temperature': temperature,
      'messages': body,
    };
    if (tools.isNotEmpty) {
      out['tools'] = tools.map(toolJson).toList();
      out['tool_choice'] = 'auto';
    }
    return out;
  }

  /// One POST with the JSON body. The streaming and the one-shot path share it.
  Future<HttpClientRequest> _open(Map<String, Object?> body) async {
    final HttpClientRequest req = await _client.postUrl(endpoint());
    req.headers.contentType = ContentType.json;
    if (apiKey.trim().isNotEmpty) {
      req.headers.set('Authorization', 'Bearer ${apiKey.trim()}');
    }
    req.write(jsonEncode(body));
    return req;
  }

  @override
  Future<LlmReply> chat({
    required String system,
    required List<LlmMessage> messages,
    required List<ToolSpec> tools,
    CancelToken? cancel,
    void Function(String delta)? onText,
  }) async {
    if (!configured) {
      throw LlmException('还没有填模型地址或模型名。');
    }
    final Map<String, Object?> body = payload(
      system: system,
      messages: messages,
      tools: tools,
    );
    final bool wantsStream = onText != null;
    if (wantsStream) {
      body['stream'] = true;
      body['stream_options'] = <String, Object?>{'include_usage': true};
    }
    HttpClientResponse res = await (await _open(body)).close();
    if (wantsStream && res.statusCode >= 400 && res.statusCode < 500) {
      // 有的服务端不认 stream 参数，退回一次不流式的请求。
      await res.drain<void>();
      body.remove('stream');
      body.remove('stream_options');
      res = await (await _open(body)).close();
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final String error = await res.transform(utf8.decoder).join();
      final String trimmed = error.length > 400 ? error.substring(0, 400) : error;
      throw LlmException('模型返回 HTTP ${res.statusCode}：$trimmed');
    }
    final String mime = res.headers.contentType?.mimeType ?? '';
    if (onText != null && mime.contains('event-stream')) {
      return _readStream(
        res.transform(utf8.decoder).transform(const LineSplitter()),
        onText,
        cancel,
      );
    }
    final String whole = await res.transform(utf8.decoder).join();
    final Object? decoded = _decodeJson(whole);
    if (decoded is Map) {
      return parseChatResponse(Map<String, Object?>.from(decoded));
    }
    if (onText == null) {
      throw LlmException('模型返回的不是 JSON 对象。');
    }
    // 头不是 event-stream，内容却是流，照样一行一行读。
    return _readStream(Stream<String>.fromIterable(whole.split('\n')), onText, cancel);
  }

  void close() => _client.close(force: true);
}

Object? _decodeJson(String text) {
  try {
    return jsonDecode(text);
  } catch (_) {
    return null;
  }
}

Map<String, Object?> messageJson(LlmMessage m) {
  switch (m.role) {
    case LlmRole.system:
      return <String, Object?>{'role': 'system', 'content': m.text};
    case LlmRole.user:
      if (m.images.isEmpty) {
        return <String, Object?>{'role': 'user', 'content': m.text};
      }
      return <String, Object?>{
        'role': 'user',
        'content': <Object?>[
          if (m.text.trim().isNotEmpty)
            <String, Object?>{'type': 'text', 'text': m.text},
          for (final String url in m.images)
            <String, Object?>{
              'type': 'image_url',
              'image_url': <String, Object?>{'url': url},
            },
        ],
      };
    case LlmRole.tool:
      return <String, Object?>{
        'role': 'tool',
        'tool_call_id': m.toolCallId,
        'content': m.text,
      };
    case LlmRole.assistant:
      final Map<String, Object?> out = <String, Object?>{
        'role': 'assistant',
        'content': m.text,
      };
      if (m.calls.isNotEmpty) {
        out['tool_calls'] = m.calls
            .map((LlmToolCall c) => <String, Object?>{
                  'id': c.id,
                  'type': 'function',
                  'function': <String, Object?>{
                    'name': c.name,
                    'arguments': jsonEncode(c.args),
                  },
                })
            .toList();
      }
      return out;
  }
}

Map<String, Object?> toolJson(ToolSpec t) => <String, Object?>{
      'type': 'function',
      'function': <String, Object?>{
        'name': t.name,
        'description': t.description,
        'parameters': t.schema,
      },
    };

/// Reads one `choices[0].message` object. Kept public for tests.
LlmReply parseChatResponse(Map<String, Object?> json) {
  final Object? choices = json['choices'];
  if (choices is! List || choices.isEmpty) {
    throw LlmException('模型返回里没有 choices。');
  }
  final Object? first = choices.first;
  if (first is! Map) {
    throw LlmException('choices 的结构不对。');
  }
  final Object? message = first['message'];
  if (message is! Map) {
    throw LlmException('message 缺失。');
  }
  final String text = '${message['content'] ?? ''}';
  final List<LlmToolCall> calls = <LlmToolCall>[];
  final Object? rawCalls = message['tool_calls'];
  if (rawCalls is List) {
    for (final Object? raw in rawCalls) {
      if (raw is! Map) continue;
      final Object? fn = raw['function'];
      if (fn is! Map) continue;
      final String name = '${fn['name'] ?? ''}';
      if (name.isEmpty) continue;
      final Map<String, Object?> args = _decodeArgs(fn['arguments']);
      calls.add(LlmToolCall(
        id: '${raw['id'] ?? name}',
        name: name,
        args: args,
      ));
    }
  }
  LlmUsage usage = const LlmUsage();
  final Object? rawUsage = json['usage'];
  if (rawUsage is Map) {
    usage = usageFrom(rawUsage);
  }
  return LlmReply(text: text, calls: calls, usage: usage);
}

Map<String, Object?> _decodeArgs(Object? raw) {
  if (raw is Map) return Map<String, Object?>.from(raw);
  if (raw is String) {
    final String text = raw.trim();
    if (text.isEmpty) return <String, Object?>{};
    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } catch (_) {
      // fall through
    }
  }
  return <String, Object?>{};
}

int _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

class _ToolAcc {
  String id = '';
  String name = '';
  final StringBuffer args = StringBuffer();
}

/// Server-sent events: `data: {...}` lines, one delta each, `[DONE]` at the end.
/// A cancelled turn stops reading at the next delta instead of draining the
/// rest of the answer.
Future<LlmReply> _readStream(
  Stream<String> lines,
  void Function(String delta)? onText,
  CancelToken? cancel,
) async {
  final StringBuffer text = StringBuffer();
  final Map<int, _ToolAcc> tools = <int, _ToolAcc>{};
  LlmUsage usage = const LlmUsage();
  await for (final String line in lines) {
    if (cancel?.cancelled ?? false) break;
    if (!line.startsWith('data:')) continue;
    final String data = line.substring(5).trim();
    if (data.isEmpty) continue;
    if (data == '[DONE]') break;
    Object? decoded;
    try {
      decoded = jsonDecode(data);
    } catch (_) {
      continue;
    }
    if (decoded is! Map) continue;
    final Object? rawUsage = decoded['usage'];
    if (rawUsage is Map) usage = usageFrom(rawUsage);
    final Object? choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) continue;
    final Object? first = choices.first;
    if (first is! Map) continue;
    final Object? delta = first['delta'];
    if (delta is! Map) continue;
    final Object? content = delta['content'];
    if (content is String && content.isNotEmpty) {
      text.write(content);
      onText?.call(content);
    }
    final Object? calls = delta['tool_calls'];
    if (calls is List) {
      for (final Object? raw in calls) {
        if (raw is! Map) continue;
        final int index = (raw['index'] as num?)?.toInt() ?? 0;
        final _ToolAcc acc = tools.putIfAbsent(index, () => _ToolAcc());
        final Object? id = raw['id'];
        if (id is String && id.isNotEmpty) acc.id = id;
        final Object? fn = raw['function'];
        if (fn is Map) {
          final Object? name = fn['name'];
          if (name is String && name.isNotEmpty) acc.name = name;
          final Object? args = fn['arguments'];
          if (args is String) acc.args.write(args);
        }
      }
    }
  }
  final List<LlmToolCall> calls = <LlmToolCall>[];
  final List<int> keys = tools.keys.toList()..sort();
  for (final int k in keys) {
    final _ToolAcc acc = tools[k]!;
    if (acc.name.isEmpty) continue;
    calls.add(LlmToolCall(
      id: acc.id.isEmpty ? 'call_$k' : acc.id,
      name: acc.name,
      args: _decodeArgs(acc.args.toString()),
    ));
  }
  return LlmReply(text: text.toString(), calls: calls, usage: usage);
}

/// Reads usage in both the OpenAI shape and the DeepSeek cache fields.
LlmUsage usageFrom(Object? raw) {
  if (raw is! Map) return const LlmUsage();
  int cached = 0;
  final Object? details = raw['prompt_tokens_details'];
  if (details is Map) cached = _asInt(details['cached_tokens']);
  if (cached == 0) cached = _asInt(raw['prompt_cache_hit_tokens']);
  return LlmUsage(
    prompt: _asInt(raw['prompt_tokens']),
    completion: _asInt(raw['completion_tokens']),
    cached: cached,
  );
}
