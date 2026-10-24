import 'dart:io';

/// Append-only record of what the agent did.
abstract class Journal {
  void add(Map<String, Object?> event);
}

class MemoryJournal implements Journal {
  final List<Map<String, Object?>> events = <Map<String, Object?>>[];

  @override
  void add(Map<String, Object?> event) {
    events.add(<String, Object?>{
      'at': DateTime.now().toUtc().toIso8601String(),
      ...event,
    });
  }
}

/// One JSON object per line, so every step survives a process kill.
class FileJournal implements Journal {
  FileJournal(this.file);

  final File file;
  IOSink? _sink;

  IOSink get _out {
    final IOSink? open = _sink;
    if (open != null) return open;
    file.parent.createSync(recursive: true);
    final IOSink created = file.openWrite(mode: FileMode.append);
    _sink = created;
    return created;
  }

  @override
  void add(Map<String, Object?> event) {
    final String line = jsonLine(<String, Object?>{
      'at': DateTime.now().toUtc().toIso8601String(),
      ...event,
    });
    try {
      _out.writeln(line);
    } catch (_) {
      // A broken log must never break a run.
    }
  }

  Future<void> close() async {
    final IOSink? open = _sink;
    if (open == null) return;
    try {
      await open.flush();
      await open.close();
    } catch (_) {
      // ignore
    }
    _sink = null;
  }
}

String jsonLine(Map<String, Object?> event) {
  final StringBuffer b = StringBuffer('{');
  bool first = true;
  event.forEach((String k, Object? v) {
    if (!first) b.write(',');
    first = false;
    b.write('"');
    b.write(k);
    b.write('":');
    b.write(_value(v));
  });
  b.write('}');
  return b.toString();
}

String _value(Object? v) {
  if (v == null) return 'null';
  if (v is num || v is bool) return '$v';
  if (v is Map) {
    final Map<String, Object?> m = <String, Object?>{};
    v.forEach((Object? k, Object? val) => m['$k'] = val);
    return jsonLine(m);
  }
  if (v is Iterable) {
    return '[${(v as Iterable<Object?>).map<String>(_value).join(',')}]';
  }
  return _quote('$v');
}

String _quote(String s) {
  final StringBuffer b = StringBuffer('"');
  for (final int unit in s.runes) {
    if (unit == 0x22) {
      b.write(r'\"');
    } else if (unit == 0x5c) {
      b.write(r'\\');
    } else if (unit < 0x20) {
      b.write(r'\u00');
      b.write(unit.toRadixString(16).padLeft(2, '0'));
    } else {
      b.writeCharCode(unit);
    }
  }
  b.write('"');
  return b.toString();
}
