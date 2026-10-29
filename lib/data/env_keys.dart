import 'dart:convert';
import 'dart:io';

import 'secrets.dart';

/// 一把环境密钥的名字和它的说明。值不在这里，在安全存储里。
class EnvKey {
  EnvKey({required this.name, this.note = '', this.at = ''});

  /// 大写下划线，像 `OPENAI_KEY` 那样。
  String name;
  String note;

  /// 最后一次动它的时间。
  String at;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        if (note.isNotEmpty) 'note': note,
        if (at.isNotEmpty) 'at': at,
      };

  static EnvKey fromJson(Map<String, Object?> json) => EnvKey(
        name: '${json['name'] ?? ''}',
        note: '${json['note'] ?? ''}',
        at: '${json['at'] ?? ''}',
      );
}

/// 一次操作。只记「谁在什么时候动了哪一把」，不记值。
class EnvOp {
  EnvOp({required this.at, required this.name, required this.action, required this.by});

  final String at;
  final String name;

  /// `set` / `delete` / `rotate`
  final String action;

  /// `user` 或 `ai`
  final String by;

  String get actionLabel => switch (action) {
        'set' => '写入',
        'delete' => '删除',
        'rotate' => '更新',
        _ => action,
      };

  String get byLabel => by == 'ai' ? 'AI 代写' : '自己写';

  Map<String, Object?> toJson() => <String, Object?>{
        'at': at,
        'name': name,
        'action': action,
        'by': by,
      };

  static EnvOp fromJson(Map<String, Object?> json) => EnvOp(
        at: '${json['at'] ?? ''}',
        name: '${json['name'] ?? ''}',
        action: '${json['action'] ?? ''}',
        by: '${json['by'] ?? ''}',
      );
}

/// 名字只认大写字母、数字和下划线，且不以数字开头。
final RegExp _kName = RegExp(r'^[A-Z_][A-Z0-9_]{0,63}$');

bool validEnvName(String name) => _kName.hasMatch(name);

/// 脱敏：只露末尾两位，其余一律圆点。短值一个都不露。
String maskEnvValue(String value) {
  if (value.isEmpty) return '未设';
  if (value.length <= 4) return '••••';
  return '••••${value.substring(value.length - 2)}';
}

/// 环境密钥：名字、说明、操作日志存在一个 JSON 里，值走安全存储。
///
/// 日志只写「谁动了哪一把」，任何一行都不带值。
class EnvBook {
  EnvBook(this.file, this.secrets);

  final File file;
  final SecretStore secrets;

  final List<EnvKey> _keys = <EnvKey>[];
  final List<EnvOp> _log = <EnvOp>[];

  /// 日志最多留这么多条。
  static const int maxLog = 200;

  List<EnvKey> get all => List<EnvKey>.unmodifiable(_keys);

  /// 最新的在前。
  List<EnvOp> get log => List<EnvOp>.unmodifiable(_log.reversed.toList());

  String secretKeyOf(String name) => 'env:$name';

  EnvKey? byName(String name) {
    for (final EnvKey k in _keys) {
      if (k.name == name) return k;
    }
    return null;
  }

  Future<void> load() async {
    _keys.clear();
    _log.clear();
    if (!file.existsSync()) return;
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      final Object? keys = decoded['keys'];
      if (keys is List) {
        for (final Object? raw in keys) {
          if (raw is! Map) continue;
          final EnvKey k = EnvKey.fromJson(Map<String, Object?>.from(raw));
          if (!validEnvName(k.name)) continue;
          _keys.add(k);
        }
      }
      final Object? log = decoded['log'];
      if (log is List) {
        for (final Object? raw in log) {
          if (raw is! Map) continue;
          _log.add(EnvOp.fromJson(Map<String, Object?>.from(raw)));
        }
      }
    } catch (_) {
      // 文件坏了从空清单开始，不挡住应用起来。
    }
  }

  Future<void> save() async {
    file.parent.createSync(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'keys': _keys.map((EnvKey k) => k.toJson()).toList(),
      'log': _log.map((EnvOp o) => o.toJson()).toList(),
    }));
  }

  /// 这一把现在的值。没有就是空串。
  Future<String> value(String name) => secrets.read(secretKeyOf(name));

  /// 写一把。已经有同名的就算更新，记成 `rotate`。
  Future<EnvKey> set(String name, String value, {String note = '', String by = 'user'}) async {
    final EnvKey? before = byName(name);
    final String at = DateTime.now().toIso8601String();
    final EnvKey key = before ?? EnvKey(name: name);
    key
      ..at = at
      ..note = note.isEmpty ? key.note : note;
    if (before == null) _keys.add(key);
    await secrets.write(secretKeyOf(name), value);
    _note(EnvOp(
        at: at, name: name, action: before == null ? 'set' : 'rotate', by: by));
    await save();
    return key;
  }

  /// 免得旧值留着：改名的时候先把新的写进去，再把旧名字删掉。
  Future<void> remove(String name, {String by = 'user'}) async {
    _keys.removeWhere((EnvKey k) => k.name == name);
    await secrets.delete(secretKeyOf(name));
    _note(EnvOp(
        at: DateTime.now().toIso8601String(), name: name, action: 'delete', by: by));
    await save();
  }

  void _note(EnvOp op) {
    _log.add(op);
    if (_log.length > maxLog) _log.removeRange(0, _log.length - maxLog);
  }

  /// 界面上每一行右边那个圆点尾巴。
  Future<Map<String, String>> masked() async {
    final Map<String, String> out = <String, String>{};
    for (final EnvKey k in _keys) {
      final String v = await secrets.read(secretKeyOf(k.name));
      out[k.name] = maskEnvValue(v);
    }
    return out;
  }
}
