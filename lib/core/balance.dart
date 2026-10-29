/// 账户里还剩多少钱。
///
/// 只有服务商给了查询接口才问得到：知道的那几家按它们各自的地址和形状解析，
/// 其余一律返回 null —— 界面上就不显示，而不是弹一个问不到的错误。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 查回来的一次余额。
class AccountBalance {
  const AccountBalance({
    required this.remaining,
    this.currency = 'CNY',
    this.granted = 0,
    this.toppedUp = 0,
  });

  /// 还能花多少。
  final double remaining;

  /// `CNY` / `USD`，服务商给什么就是什么。
  final String currency;

  /// 赠送的那部分，和充值的那部分。服务商不给就是 0。
  final double granted;
  final double toppedUp;

  /// `¥12.34` / `$1.20` / `12.34 EUR`。
  String get text {
    final String amount = remaining.toStringAsFixed(2);
    switch (currency.toUpperCase()) {
      case 'CNY':
      case 'RMB':
        return '¥$amount';
      case 'USD':
        return '\$$amount';
    }
    return '$amount ${currency.toUpperCase()}';
  }
}

/// 这个地址能不能问余额：能就给出接口地址，不能就给 null。
///
/// 认 DeepSeek、Moonshot、OpenRouter、SiliconFlow 四家，地址按 OpenAI 那套写法过来，
/// 末尾带不带 `/v1`、带不带 `/chat/completions` 都行。
Uri? balanceEndpoint(String baseUrl) {
  String base = baseUrl.trim();
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  const String chat = '/chat/completions';
  if (base.endsWith(chat)) base = base.substring(0, base.length - chat.length);
  final Uri? uri = Uri.tryParse(base);
  if (uri == null || uri.host.isEmpty) return null;
  final String host = uri.host.toLowerCase();
  final bool hasV1 = base.endsWith('/v1');
  String tail;
  if (host.contains('deepseek')) {
    if (hasV1) base = base.substring(0, base.length - 3);
    tail = '/user/balance';
  } else if (host.contains('moonshot')) {
    tail = hasV1 ? '/users/me/balance' : '/v1/users/me/balance';
  } else if (host.contains('openrouter')) {
    tail = hasV1 ? '/credits' : '/api/v1/credits';
  } else if (host.contains('siliconflow')) {
    tail = hasV1 ? '/user/info' : '/v1/user/info';
  } else {
    return null;
  }
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  return Uri.tryParse('$base$tail');
}

/// 各家回的那一坨 JSON → 余额。认不出来就给 null。
AccountBalance? parseBalance(Object? json) {
  if (json is! Map) return null;
  final Map<String, Object?> m = _mapOf(json);

  // DeepSeek：{"balance_infos":[{"currency":"CNY","total_balance":"110.00",…}]}
  final Object? infos = m['balance_infos'];
  if (infos is List && infos.isNotEmpty) {
    Map<String, Object?>? pick;
    double? pickTotal;
    for (final Object? one in infos) {
      if (one is! Map) continue;
      final Map<String, Object?> row = _mapOf(one);
      final double? total = _num(row['total_balance']);
      if (total == null) continue;
      final bool cny = '${row['currency']}'.toUpperCase() == 'CNY';
      // 一个账户有两种币时按人民币说，那是多数人看的那一份。
      if (pick == null || cny) {
        pick = row;
        pickTotal = total;
      }
      if (cny) break;
    }
    if (pick != null && pickTotal != null) {
      return AccountBalance(
        remaining: pickTotal,
        currency: '${pick['currency'] ?? 'CNY'}',
        granted: _num(pick['granted_balance']) ?? 0,
        toppedUp: _num(pick['topped_up_balance']) ?? 0,
      );
    }
  }

  final Object? data = m['data'];
  if (data is Map) {
    final Map<String, Object?> d = _mapOf(data);
    // OpenRouter：{"data":{"total_credits":10,"total_usage":1.5}}
    final double? credits = _num(d['total_credits']);
    if (credits != null) {
      final double used = _num(d['total_usage']) ?? 0;
      return AccountBalance(remaining: credits - used, currency: 'USD', toppedUp: credits);
    }
    // Moonshot：{"data":{"available_balance":1.2,…}}
    final double? available = _num(d['available_balance']);
    if (available != null) return AccountBalance(remaining: available);
    // SiliconFlow：{"data":{"totalBalance":"0.88","balance":"0.88",…}}
    final double? total = _num(d['totalBalance']) ?? _num(d['balance']);
    if (total != null) return AccountBalance(remaining: total);
  }

  // 少数服务把余额放在最外层。
  final double? top = _num(m['balance']);
  if (top != null) {
    return AccountBalance(remaining: top, currency: '${m['currency'] ?? 'CNY'}');
  }
  return null;
}

/// 问一次余额。问不到（连不上、401、404、形状不认识）都当没有，不抛异常。
class BalanceProbe {
  BalanceProbe({HttpClient? client}) : _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 8);
  }

  final HttpClient _client;
  bool _closed = false;

  Future<AccountBalance?> fetch({required String baseUrl, required String apiKey}) async {
    final Uri? url = balanceEndpoint(baseUrl);
    if (url == null) return null;
    try {
      final HttpClientRequest req = await _client.getUrl(url);
      req.headers.set('Accept', 'application/json');
      if (apiKey.trim().isNotEmpty) {
        req.headers.set('Authorization', 'Bearer ${apiKey.trim()}');
      }
      final HttpClientResponse res = await req.close();
      final String body = await utf8.decoder.bind(res).join();
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      return parseBalance(jsonDecode(body));
    } catch (_) {
      return null;
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _client.close(force: true);
  }
}

Map<String, Object?> _mapOf(Map<dynamic, dynamic> json) => <String, Object?>{
      for (final MapEntry<dynamic, dynamic> e in json.entries) '${e.key}': e.value,
    };

/// `"110.00"`、`110`、`"¥110.00"` 都读成 110。
double? _num(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    final String digits = value.replaceAll(RegExp(r'[^0-9.\-]'), '');
    if (digits.isEmpty) return null;
    return double.tryParse(digits);
  }
  return null;
}
