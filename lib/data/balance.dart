import 'package:flutter/foundation.dart';

import '../core/balance.dart';
import 'secrets.dart';
import 'settings.dart';

/// 对话底部那条余额。
///
/// 只有服务商给了查询接口才问得到，问不到就什么都不显示：不弹错误，也不留上一次的数字。
/// 一轮跑完问一次，连着几轮之间隔十二秒，免得每说一句都去敲一次接口。
class BalanceStore extends ChangeNotifier {
  BalanceStore(this.settings, this.secrets);

  final SettingsStore settings;
  final SecretStore secrets;

  AccountBalance? _value;
  bool _loading = false;
  String _for = '';
  DateTime _at = DateTime.fromMillisecondsSinceEpoch(0);
  BalanceProbe? _probe;
  bool _disposed = false;

  /// 最近一次问到的余额。问不到就是 null。
  AccountBalance? get value => _value;

  /// 正在问。第一次问的时候界面可以先写个「余额 …」。
  bool get loading => _loading;

  static const Duration _gap = Duration(seconds: 12);

  /// 这套配置能不能问余额：地址认得出来就有接口。
  static bool supports(String baseUrl) => balanceEndpoint(baseUrl) != null;

  /// 问一句。同一套配置十二秒内只问一次，[force] 是点一下那颗数字的时候。
  Future<void> refresh(ModelProfile profile, {bool force = false}) async {
    final String base = profile.baseUrl.trim();
    if (!supports(base)) {
      _for = '';
      if (_value != null) {
        _value = null;
        _notify();
      }
      return;
    }
    final String tag = '${profile.id}|$base';
    if (!force && tag == _for && DateTime.now().difference(_at) < _gap) return;
    if (_loading) return;
    _loading = true;
    _notify();
    final BalanceProbe probe = _probe ??= BalanceProbe();
    String key = await secrets.read(modelSecretKeyFor(profile.id));
    // 老的单一密钥还在顶一阵子的时候照样能用。
    if (key.isEmpty) key = await secrets.read(modelSecretKey());
    final AccountBalance? got = await probe.fetch(baseUrl: base, apiKey: key);
    if (_disposed) return;
    _loading = false;
    _for = tag;
    _at = DateTime.now();
    _value = got;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _probe?.close();
    super.dispose();
  }
}
