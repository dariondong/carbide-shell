import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 在线识别：把录好的一段 wav 交给网上那个认字的接口，拿回一句字。
///
/// 接口形状照 OpenAI 的 `/audio/transcriptions`（multipart 里带 `file` 与 `model`），
/// 硅基流动、Groq、OpenAI 自家的都认这一套；地址填到 `/v1` 或填整个接口地址都行。
class AsrService {
  const AsrService(this.name, this.baseUrl, this.model);

  /// 清单上那两个字。
  final String name;

  /// 填进设置里的地址。
  final String baseUrl;

  /// 默认的模型名。
  final String model;
}

/// 常见的几家。选一下就把地址和模型填好，密钥还得自己贴。
const List<AsrService> kAsrServices = <AsrService>[
  AsrService('硅基流动', 'https://api.siliconflow.cn/v1', 'FunAudioLLM/SenseVoiceSmall'),
  AsrService('OpenAI', 'https://api.openai.com/v1', 'whisper-1'),
  AsrService('Groq', 'https://api.groq.com/openai/v1', 'whisper-large-v3-turbo'),
];

/// 认字的结果：认到了 [text]，没认到就把 [error] 写清是哪一环。
class AsrResult {
  const AsrResult(this.text, this.error);

  final String text;
  final String error;

  bool get ok => text.isNotEmpty;
}

/// 填的地址补成完整的接口地址。
///
/// 三种写法都认：`https://host`（补 `/v1/audio/transcriptions`）、`https://host/v1`、
/// 以及已经写全的 `…/audio/transcriptions`。
String asrEndpoint(String baseUrl) {
  final String raw = baseUrl.trim();
  if (raw.isEmpty) return '';
  if (raw.contains('/audio/transcriptions')) return raw;
  final String base = raw.replaceAll(RegExp(r'/+$'), '');
  final Uri? uri = Uri.tryParse(base);
  if (uri == null) return '$base/audio/transcriptions';
  final String path = uri.path.replaceAll(RegExp(r'/+$'), '');
  return path.isEmpty
      ? '$base/v1/audio/transcriptions'
      : '$base/audio/transcriptions';
}

/// 把一段 wav 发过去认字。[key] 空着也发：本地自建的服务多半不要密钥。
Future<AsrResult> transcribeWav({
  required List<int> wav,
  required String baseUrl,
  required String model,
  String key = '',
  String language = 'zh',
  Duration timeout = const Duration(seconds: 45),
}) async {
  final String url = asrEndpoint(baseUrl);
  final String name = model.trim();
  if (url.isEmpty) return const AsrResult('', '没填识别地址');
  if (name.isEmpty) return const AsrResult('', '没填模型名');
  if (wav.isEmpty) return const AsrResult('', '这段录音是空的');

  const String boundary = '----carbideasr9d41c';
  final BytesBuilder body = BytesBuilder(copy: false);

  void field(String part, String value) {
    body.add(utf8.encode('--$boundary\r\n'
        'Content-Disposition: form-data; name="$part"\r\n\r\n'
        '$value\r\n'));
  }

  body.add(utf8.encode('--$boundary\r\n'
      'Content-Disposition: form-data; name="file"; filename="voice.wav"\r\n'
      'Content-Type: audio/wav\r\n\r\n'));
  body.add(wav);
  body.add(utf8.encode('\r\n'));
  field('model', name);
  if (language.trim().isNotEmpty) field('language', language.trim());
  field('response_format', 'json');
  body.add(utf8.encode('--$boundary--\r\n'));

  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12);
  try {
    final HttpClientRequest request =
        await client.postUrl(Uri.parse(url)).timeout(timeout);
    final String token = key.trim();
    if (token.isNotEmpty) {
      request.headers.set('Authorization', 'Bearer $token');
    }
    request.headers.contentType = ContentType(
      'multipart',
      'form-data',
      parameters: <String, String>{'boundary': boundary},
    );
    request.add(body.takeBytes());
    final HttpClientResponse response = await request.close().timeout(timeout);
    final String text =
        await response.transform(utf8.decoder).join().timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return AsrResult('', 'HTTP ${response.statusCode}：${_short(text)}');
    }
    final String said = parseAsrText(text);
    return AsrResult(said, said.isEmpty ? '接口没给字：${_short(text)}' : '');
  } catch (error) {
    return AsrResult('', '$error');
  } finally {
    client.close(force: true);
  }
}

/// 接口回的那段 JSON 里那句字。形状各家略有不同，常见的几种都认。
String parseAsrText(String raw) {
  final String body = raw.trim();
  if (body.isEmpty || body.startsWith('<')) return '';
  try {
    final Object? json = jsonDecode(body);
    if (json is String) return json.trim();
    if (json is Map) {
      final Object? direct = json['text'];
      if (direct is String) return direct.trim();
      for (final String key in const <String>['result', 'data', 'output']) {
        final Object? value = json[key];
        if (value is String) return value.trim();
        if (value is Map && value['text'] is String) {
          return '${value['text']}'.trim();
        }
      }
      return '';
    }
  } catch (_) {
    // 不是 JSON：有的服务直接回一行字。
  }
  return body;
}

/// 出错时那一坨最前面几十个字，够看出是密钥不对还是参数不对。
String _short(String text) {
  final String flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.length <= 120) return flat;
  return '${flat.substring(0, 120)}…';
}
