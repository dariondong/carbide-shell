import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// One conversation: its scope, its transcript, its own journal file.
class Conversation {
  Conversation({
    required this.id,
    required this.title,
    required this.hostId,
    List<LlmMessage>? messages,
    DateTime? updatedAt,
    this.autoApproveAll = false,
    List<String>? kindApprovals,
  })  : messages = messages ?? <LlmMessage>[],
        updatedAt = updatedAt ?? DateTime.now(),
        kindApprovals = kindApprovals ?? <String>[];

  final String id;
  String title;

  /// Empty means the agent may use every saved host.
  final String hostId;

  final List<LlmMessage> messages;
  DateTime updatedAt;

  /// This conversation asked for no more confirmations.
  bool autoApproveAll;

  /// Approved kinds, `tool:firstword`. Same kind runs without asking again.
  final List<String> kindApprovals;

  bool allowsKind(String kind) => autoApproveAll || kindApprovals.contains(kind);

  bool get multiHost => hostId.isEmpty;

  /// The memory scope this conversation reads and writes.
  String get scope => multiHost ? 'global' : hostId;

  int get turns => messages.where((LlmMessage m) => m.role == LlmRole.user).length;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'hostId': hostId,
        'updatedAt': updatedAt.toIso8601String(),
        'autoApproveAll': autoApproveAll,
        'kindApprovals': kindApprovals,
        'messages': messages.map(messageToJson).toList(),
      };

  static Conversation fromJson(Map<String, Object?> json) {
    final Object? list = json['messages'];
    final List<LlmMessage> messages = <LlmMessage>[];
    if (list is List) {
      for (final Object? raw in list) {
        if (raw is! Map) continue;
        final LlmMessage? m = messageFromJson(Map<String, Object?>.from(raw));
        if (m != null) messages.add(m);
      }
    }
    return Conversation(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? '未命名'}',
      hostId: '${json['hostId'] ?? ''}',
      messages: messages,
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}') ?? DateTime.now(),
      autoApproveAll: json['autoApproveAll'] == true,
      kindApprovals: (json['kindApprovals'] is List)
          ? (json['kindApprovals']! as List).map((Object? e) => '$e').toList()
          : <String>[],
    );
  }
}

Map<String, Object?> messageToJson(LlmMessage m) => <String, Object?>{
      'role': m.role.name,
      'text': m.text,
      if (m.images.isNotEmpty) 'images': m.images,
      if (m.calls.isNotEmpty)
        'calls': m.calls
            .map((LlmToolCall c) => <String, Object?>{
                  'id': c.id,
                  'name': c.name,
                  'args': c.args,
                })
            .toList(),
      if (m.toolCallId.isNotEmpty) 'toolCallId': m.toolCallId,
      if (m.toolName.isNotEmpty) 'toolName': m.toolName,
      if (m.failed) 'failed': true,
    };

LlmMessage? messageFromJson(Map<String, Object?> json) {
  final String role = '${json['role'] ?? ''}';
  final String text = '${json['text'] ?? ''}';
  final List<LlmToolCall> calls = <LlmToolCall>[];
  final Object? rawCalls = json['calls'];
  if (rawCalls is List) {
    for (final Object? raw in rawCalls) {
      if (raw is! Map) continue;
      final Object? args = raw['args'];
      calls.add(LlmToolCall(
        id: '${raw['id'] ?? ''}',
        name: '${raw['name'] ?? ''}',
        args: args is Map ? Map<String, Object?>.from(args) : <String, Object?>{},
      ));
    }
  }
  switch (role) {
    case 'user':
      final Object? rawImages = json['images'];
      final List<String> images = rawImages is List
          ? rawImages.map((Object? e) => '$e').toList()
          : const <String>[];
      return LlmMessage.user(text, images: images);
    case 'assistant':
      return LlmMessage.assistant(text, calls: calls);
    case 'tool':
      return LlmMessage.toolResult(
        text: text,
        toolCallId: '${json['toolCallId'] ?? ''}',
        toolName: '${json['toolName'] ?? ''}',
        failed: json['failed'] == true,
      );
    default:
      return null;
  }
}

/// Transcripts live as one JSON file per conversation.
class ConversationStore {
  ConversationStore(this.dir);

  final Directory dir;
  final List<Conversation> _items = <Conversation>[];

  List<Conversation> get all {
    final List<Conversation> sorted = List<Conversation>.of(_items);
    sorted.sort((Conversation a, Conversation b) => b.updatedAt.compareTo(a.updatedAt));
    return List<Conversation>.unmodifiable(sorted);
  }

  Conversation? byId(String id) {
    for (final Conversation c in _items) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> load() async {
    _items.clear();
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      return;
    }
    for (final FileSystemEntity entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final Object? decoded = jsonDecode(await entity.readAsString());
        if (decoded is Map) {
          final Conversation c = Conversation.fromJson(Map<String, Object?>.from(decoded));
          if (c.id.isNotEmpty) _items.add(c);
        }
      } catch (_) {
        // Skip a broken transcript instead of losing the rest.
      }
    }
  }

  Future<Conversation> create({required String title, String hostId = ''}) async {
    final Conversation c = Conversation(
      id: 'c${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      title: title.trim().isEmpty ? '新对话' : title.trim(),
      hostId: hostId,
    );
    _items.add(c);
    await save(c);
    return c;
  }

  Future<void> save(Conversation c) async {
    c.updatedAt = DateTime.now();
    dir.createSync(recursive: true);
    final String text = const JsonEncoder.withIndent('  ').convert(c.toJson());
    await File('${dir.path}/${c.id}.json').writeAsString(text);
  }

  Future<void> remove(String id) async {
    _items.removeWhere((Conversation c) => c.id == id);
    final File file = File('${dir.path}/$id.json');
    if (file.existsSync()) await file.delete();
  }

  File journalOf(Conversation c) => File('${dir.path}/${c.id}.journal.jsonl');
}
