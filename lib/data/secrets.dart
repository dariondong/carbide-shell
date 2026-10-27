/// Where a host's password or private key is kept. Never in the host JSON.
abstract class SecretStore {
  Future<String> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class MemorySecretStore implements SecretStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String> read(String key) async => _values[key] ?? '';

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

String hostSecretKey(String hostId) => 'host:$hostId:secret';

/// 单独存的 sudo 密码：登录用密钥、提权要密码的主机很多，别逼人用密码登录。
String hostSudoKey(String hostId) => 'host:$hostId:sudo';
String modelSecretKey() => 'model:apiKey';

/// 一套模型配置一把密钥，按配置 id 分开存。
String modelSecretKeyFor(String profileId) => 'model:$profileId:apiKey';
