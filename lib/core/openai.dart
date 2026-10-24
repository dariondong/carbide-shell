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

  @override
  Future<LlmReply> chat({
    required String system,
    required List<LlmMessage> messages,
    required List<ToolSpec> tools,
    CancelToken? cancel,
  }) async {
    if (!configured) {
      throw LlmException('还没有填模型地址或模型名。');
    }
    final HttpClientRequest req = await _client.postUrl(endpoint());
    req.headers.contentType = ContentType.json;
    if (apiKey.trim().isNotEmpty) {
      req.headers.set('Authorization', 'Bearer ${apiKey.trim()}');
    }
    req.write(jsonEncode(payload(system: system, messages: messages, tools: tools)));
    final HttpClientResponse res = await req.close();
    final String text = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final String trimmed = text.length > 400 ? text.substring(0, 400) : text;
      throw LlmException('模型返回 HTTP ${res.statusCode}：$trimmed');
    }
    final Object? decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw LlmException('模型返回的不是 JSON 对象。');
    }
    return parseChatResponse(Map<String, Object?>.from(decoded));
  }

  void close() => _client.close(force: true);
}

Map<String, Object?> messageJson(LlmMessage m) {
  switch (m.role) {
    case LlmRole.system:
      return <String, Object?>{'role': 'system', 'content': m.text};
    case LlmRole.user:
      return <String, Object?>{'role': 'user', 'content': m.text};
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
    usage = LlmUsage(
      prompt: _asInt(rawUsage['prompt_tokens']),
      completion: _asInt(rawUsage['completion_tokens']),
    );
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
