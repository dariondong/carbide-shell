import 'dart:convert';
import 'dart:io';

import 'package:carbide_shell/core/asr.dart';
import 'package:flutter_test/flutter_test.dart';

/// 在线识别：地址怎么拼、multipart 发出去的是什么、回来那句字怎么读。
void main() {
  test('地址补齐', () {
    expect(asrEndpoint(''), '');
    expect(asrEndpoint('https://api.siliconflow.cn/v1'),
        'https://api.siliconflow.cn/v1/audio/transcriptions');
    expect(asrEndpoint('https://api.siliconflow.cn/v1/'),
        'https://api.siliconflow.cn/v1/audio/transcriptions');
    expect(asrEndpoint('https://api.openai.com'),
        'https://api.openai.com/v1/audio/transcriptions');
    expect(
      asrEndpoint('https://host/v1/audio/transcriptions'),
      'https://host/v1/audio/transcriptions',
    );
  });

  test('回来那句字：几种形状都认', () {
    expect(parseAsrText('{"text":"你好"}'), '你好');
    expect(parseAsrText('{"result":"你好"}'), '你好');
    expect(parseAsrText('{"data":{"text":"你好"}}'), '你好');
    expect(parseAsrText('{"output":"你好"}'), '你好');
    expect(parseAsrText(' 你好 '), '你好');
    expect(parseAsrText('<html>bad</html>'), '');
    expect(parseAsrText(''), '');
    expect(parseAsrText('{"text":""}'), '');
  });

  test('真发一次：字段齐、密钥带上、正文里那句字读得回来', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    HttpRequest? seen;
    String body = '';
    final Future<void> served = () async {
      await for (final HttpRequest request in server) {
        seen = request;
        body = await utf8.decodeStream(request);
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write('{"text":"磁盘还剩一半"}');
        await request.response.close();
      }
    }();
    addTearDown(() async {
      await server.close(force: true);
      await served;
    });

    final AsrResult result = await transcribeWav(
      wav: const <int>[82, 73, 70, 70, 0, 0, 0, 0],
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
      model: 'whisper-1',
      key: 'sk-test',
    );
    expect(result.ok, isTrue);
    expect(result.text, '磁盘还剩一半');
    expect(seen?.uri.path, '/v1/audio/transcriptions');
    expect(seen?.headers.value('authorization'), 'Bearer sk-test');
    expect(seen?.headers.contentType?.mimeType, 'multipart/form-data');
    expect(seen?.headers.contentType?.parameters['boundary'], isNotEmpty);
    expect(body, contains('name="model"\r\n\r\nwhisper-1'));
    expect(body, contains('name="language"\r\n\r\nzh'));
    expect(body, contains('filename="voice.wav"'));
    expect(body, contains('Content-Type: audio/wav'));
  });

  test('接口报错时把状态码与那一句写出来', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final Future<void> served = () async {
      await for (final HttpRequest request in server) {
        await utf8.decodeStream(request);
        request.response
          ..statusCode = 401
          ..write('{"error":{"message":"invalid api key"}}');
        await request.response.close();
      }
    }();
    addTearDown(() async {
      await server.close(force: true);
      await served;
    });

    final AsrResult result = await transcribeWav(
      wav: const <int>[1, 2, 3],
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
      model: 'whisper-1',
      key: 'bad',
    );
    expect(result.ok, isFalse);
    expect(result.error, contains('401'));
    expect(result.error, contains('invalid api key'));
  });

  test('没填地址或模型名就不发请求', () async {
    expect(
      (await transcribeWav(wav: const <int>[1], baseUrl: '', model: 'x')).error,
      contains('地址'),
    );
    expect(
      (await transcribeWav(
        wav: const <int>[1],
        baseUrl: 'https://host/v1',
        model: ' ',
      ))
          .error,
      contains('模型'),
    );
    expect(
      (await transcribeWav(
        wav: const <int>[],
        baseUrl: 'https://host/v1',
        model: 'x',
      ))
          .error,
      contains('空'),
    );
  });
}
