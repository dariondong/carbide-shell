import 'package:carbide_shell/core/balance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DeepSeek 那一种：balance_infos 里挑人民币那一份', () {
    final AccountBalance? one = parseBalance(<String, Object?>{
      'is_available': true,
      'balance_infos': <Object?>[
        <String, Object?>{
          'currency': 'USD',
          'total_balance': '3.10',
          'granted_balance': '0.00',
          'topped_up_balance': '3.10',
        },
        <String, Object?>{
          'currency': 'CNY',
          'total_balance': '110.00',
          'granted_balance': '10.00',
          'topped_up_balance': '100.00',
        },
      ],
    });
    expect(one, isNotNull);
    expect(one!.remaining, 110.0);
    expect(one.currency, 'CNY');
    expect(one.granted, 10.0);
    expect(one.text, '¥110.00');
  });

  test('只有一份的时候就用那一份，币种跟着走', () {
    final AccountBalance? one = parseBalance(<String, Object?>{
      'balance_infos': <Object?>[
        <String, Object?>{'currency': 'USD', 'total_balance': '1.5'},
      ],
    });
    expect(one!.remaining, 1.5);
    expect(one.text, '\$1.50');
  });

  test('Moonshot 的 available_balance', () {
    final AccountBalance? one = parseBalance(<String, Object?>{
      'status': true,
      'data': <String, Object?>{'available_balance': 12.34, 'cash_balance': 10},
    });
    expect(one!.remaining, 12.34);
    expect(one.currency, 'CNY');
  });

  test('OpenRouter 的花掉多少要减掉', () {
    final AccountBalance? one = parseBalance(<String, Object?>{
      'data': <String, Object?>{'total_credits': 10, 'total_usage': 1.5},
    });
    expect(one!.remaining, 8.5);
    expect(one.text, '\$8.50');
  });

  test('SiliconFlow 的字符串余额', () {
    final AccountBalance? one = parseBalance(<String, Object?>{
      'data': <String, Object?>{'balance': '0.88', 'totalBalance': '¥0.88'},
    });
    expect(one!.remaining, 0.88);
  });

  test('认不出来就是 null，不猜', () {
    expect(parseBalance(null), isNull);
    expect(parseBalance(<String, Object?>{'error': 'nope'}), isNull);
    expect(parseBalance(<Object?>[]), isNull);
    expect(parseBalance(<String, Object?>{'balance_infos': <Object?>[]}), isNull);
  });

  test('接口地址：认那四家，末尾带不带 /v1 都行', () {
    expect(balanceEndpoint('https://api.deepseek.com').toString(),
        'https://api.deepseek.com/user/balance');
    expect(balanceEndpoint('https://api.deepseek.com/v1/').toString(),
        'https://api.deepseek.com/user/balance');
    expect(balanceEndpoint('https://api.deepseek.com/v1/chat/completions').toString(),
        'https://api.deepseek.com/user/balance');
    expect(balanceEndpoint('https://api.moonshot.cn/v1').toString(),
        'https://api.moonshot.cn/v1/users/me/balance');
    expect(balanceEndpoint('https://api.moonshot.cn').toString(),
        'https://api.moonshot.cn/v1/users/me/balance');
    expect(balanceEndpoint('https://openrouter.ai/api/v1').toString(),
        'https://openrouter.ai/api/v1/credits');
    expect(balanceEndpoint('https://api.siliconflow.cn/v1').toString(),
        'https://api.siliconflow.cn/v1/user/info');
  });

  test('不认识的地址不问', () {
    expect(balanceEndpoint(''), isNull);
    expect(balanceEndpoint('https://api.example.com/v1'), isNull);
  });
}
