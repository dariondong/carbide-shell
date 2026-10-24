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
String modelSecretKey() => 'model:apiKey';
