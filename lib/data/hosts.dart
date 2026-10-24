import 'dart:convert';
import 'dart:io';

/// One machine the agent may operate.
class HostEntry {
  HostEntry({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    this.user = 'root',
    this.auth = 'password',
    this.fingerprint = '',
  });

  HostEntry copyWith({
    String? name,
    String? host,
    int? port,
    String? user,
    String? auth,
    String? fingerprint,
  }) {
    return HostEntry(
      id: id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      user: user ?? this.user,
      auth: auth ?? this.auth,
      fingerprint: fingerprint ?? this.fingerprint,
    );
  }

  final String id;
  final String name;
  final String host;
  final int port;
  final String user;

  /// `password` or `key`. The secret itself never lives in this object.
  final String auth;

  /// OpenSSH-style `SHA256:…` recorded on first connect.
  final String fingerprint;

  String get address => '$user@$host:$port';

  bool get trusted => fingerprint.isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'user': user,
        'auth': auth,
        'fingerprint': fingerprint,
      };

  static HostEntry fromJson(Map<String, Object?> json) => HostEntry(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        host: '${json['host'] ?? ''}',
        port: (json['port'] as num?)?.toInt() ?? 22,
        user: '${json['user'] ?? 'root'}',
        auth: '${json['auth'] ?? 'password'}',
        fingerprint: '${json['fingerprint'] ?? ''}',
      );
}

/// The host list, persisted as one JSON file next to the app's data.
class HostStore {
  HostStore(this.file);

  final File file;
  final List<HostEntry> _hosts = <HostEntry>[];

  List<HostEntry> get hosts => List<HostEntry>.unmodifiable(_hosts);

  Future<void> load() async {
    _hosts.clear();
    if (!file.existsSync()) return;
    try {
      final String text = await file.readAsString();
      final Object? decoded = jsonDecode(text);
      if (decoded is Map) {
        final Object? list = decoded['hosts'];
        if (list is List) {
          for (final Object? raw in list) {
            if (raw is Map) {
              _hosts.add(HostEntry.fromJson(Map<String, Object?>.from(raw)));
            }
          }
        }
      }
    } catch (_) {
      // A broken file starts empty; it must not block the app.
    }
  }

  Future<void> save() async {
    file.parent.createSync(recursive: true);
    final String text = const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'hosts': _hosts.map((HostEntry h) => h.toJson()).toList(),
    });
    await file.writeAsString(text);
  }

  HostEntry? byName(String name) {
    final String key = name.trim().toLowerCase();
    for (final HostEntry h in _hosts) {
      if (h.name.toLowerCase() == key) return h;
    }
    return null;
  }

  HostEntry? byId(String id) {
    for (final HostEntry h in _hosts) {
      if (h.id == id) return h;
    }
    return null;
  }

  Future<void> upsert(HostEntry entry) async {
    final int index = _hosts.indexWhere((HostEntry h) => h.id == entry.id);
    if (index >= 0) {
      _hosts[index] = entry;
    } else {
      _hosts.add(entry);
    }
    await save();
  }

  Future<void> remove(String id) async {
    _hosts.removeWhere((HostEntry h) => h.id == id);
    await save();
  }

  Future<void> setFingerprint(String id, String fingerprint) async {
    final HostEntry? h = byId(id);
    if (h == null) return;
    await upsert(h.copyWith(fingerprint: fingerprint));
  }

  static String newId() {
    final int ms = DateTime.now().millisecondsSinceEpoch;
    return 'h${ms.toRadixString(36)}';
  }
}
