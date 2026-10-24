import 'dart:convert';
import 'dart:io';

/// One thing the agent should keep knowing between sessions.
class MemoryEntry {
  MemoryEntry({
    required this.id,
    required this.text,
    this.tag = '',
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final String id;
  final String text;

  /// 偏好 / 主机 / 规则 / 空。
  final String tag;
  final DateTime at;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'text': text,
        'tag': tag,
        'at': at.toIso8601String(),
      };

  static MemoryEntry fromJson(Map<String, Object?> json) => MemoryEntry(
        id: '${json['id'] ?? ''}',
        text: '${json['text'] ?? ''}',
        tag: '${json['tag'] ?? ''}',
        at: DateTime.tryParse('${json['at'] ?? ''}') ?? DateTime.now(),
      );
}

/// The long-term memory list, one JSON file next to the app data.
class MemoryStore {
  MemoryStore(this.file);

  final File file;
  final List<MemoryEntry> _entries = <MemoryEntry>[];

  List<MemoryEntry> get entries => List<MemoryEntry>.unmodifiable(_entries);

  int get length => _entries.length;

  Future<void> load() async {
    _entries.clear();
    if (!file.existsSync()) return;
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        final Object? list = decoded['entries'];
        if (list is List) {
          for (final Object? raw in list) {
            if (raw is Map) {
              final MemoryEntry e = MemoryEntry.fromJson(Map<String, Object?>.from(raw));
              if (e.text.trim().isNotEmpty) _entries.add(e);
            }
          }
        }
      }
    } catch (_) {
      // A broken file starts empty.
    }
  }

  Future<void> save() async {
    file.parent.createSync(recursive: true);
    final String text = const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'entries': _entries.map((MemoryEntry e) => e.toJson()).toList(),
    });
    await file.writeAsString(text);
  }

  Future<MemoryEntry> add(String text, {String tag = ''}) async {
    final MemoryEntry entry = MemoryEntry(
      id: 'm${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      text: text.trim(),
      tag: tag.trim(),
    );
    if (entry.text.isEmpty) return entry;
    _entries.insert(0, entry);
    await save();
    return entry;
  }

  Future<void> update(String id, {String? text, String? tag}) async {
    final int index = _entries.indexWhere((MemoryEntry e) => e.id == id);
    if (index < 0) return;
    final MemoryEntry old = _entries[index];
    _entries[index] = MemoryEntry(
      id: old.id,
      text: (text ?? old.text).trim(),
      tag: (tag ?? old.tag).trim(),
      at: old.at,
    );
    await save();
  }

  Future<void> remove(String id) async {
    _entries.removeWhere((MemoryEntry e) => e.id == id);
    await save();
  }

  /// What goes into the system prompt. The newest entries win when the cap
  /// bites, then the kept ones are printed oldest first.
  String renderForPrompt({int maxChars = 1200}) {
    if (_entries.isEmpty) return '';
    final List<String> lines = <String>[];
    int used = 0;
    for (final MemoryEntry e in _entries) {
      final String line = '${e.tag.isEmpty ? '' : '[${e.tag}] '}${e.text}';
      if (used + line.length > maxChars) break;
      lines.add(line);
      used += line.length + 3;
    }
    if (lines.isEmpty) return '';
    final StringBuffer b = StringBuffer('长期记忆（本机保存，可能过时，和当前观察冲突时以观察为准）\n');
    for (final String line in lines.reversed) {
      b.writeln('- $line');
    }
    return b.toString();
  }
}
