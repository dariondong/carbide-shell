import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'models.dart';
import 'plan.dart';

/// 一份记录最多留这么多字，多出来的从最早的收起。
///
/// 手机上记录越长越难办：打开对话要把它整份读回来，每轮跑完要把它整份写回去，
/// 一部长记录能把这个过程拖到几秒并且吃掉几十兆内存。收在上下文的十几倍，
/// 回看还够用，读写也不至于把手机拖住。
const int kTranscriptMaxChars = 1000000;

/// 一条记录在预算里算多少字。正文、工具参数、图片都算，图片是最重的那部分。
int messageWeight(LlmMessage m) {
  int n = m.text.length + 24;
  for (final LlmToolCall c in m.calls) {
    n += c.name.length + 8;
    c.args.forEach((String key, Object? value) {
      n += key.length + 4;
      if (value is String) n += value.length;
    });
  }
  for (final String url in m.images) {
    n += url.length;
  }
  return n;
}

/// 记录超过 [maxChars] 就把最早的那些从 [messages] 里删掉，返回删了几条。
///
/// 只保尾部那一块：最新那一条无论如何留着，也不从一条工具结果开头，
/// 否则模型看到的是一句没头没尾的输出。
int trimTranscript(
  List<LlmMessage> messages, {
  int maxChars = kTranscriptMaxChars,
}) {
  int acc = 0;
  int cut = 0;
  for (int i = messages.length - 1; i >= 0; i -= 1) {
    acc += messageWeight(messages[i]);
    if (acc > maxChars && i < messages.length - 1) {
      cut = i + 1;
      break;
    }
  }
  while (cut < messages.length && messages[cut].role == LlmRole.tool) {
    cut += 1;
  }
  if (cut <= 0) return 0;
  messages.removeRange(0, cut);
  return cut;
}

/// One conversation: its scope, its transcript, its own journal file.
class Conversation {
  Conversation({
    required this.id,
    required this.title,
    required this.hostId,
    List<LlmMessage>? messages,
    DateTime? updatedAt,
    this.autoApproveAll = false,
    this.tokensUsed = 0,
    this.systemPrompt = '',
    this.advanceMaster = false,
    this.dropped = 0,
    this.costCny = 0,
    this.plan,
    this.planAnchor = 0,
    this.profileId = '',
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

  /// Tokens spent across every turn of this conversation.
  int tokensUsed;

  /// 这个对话自己的系统提示词。空着表示跟设置走。
  String systemPrompt;

  /// 这场对话钉在哪套模型配置上。空着就是设置里选中的那一套。
  String profileId;

  /// Advance Master：管全部主机，还能把新主机写进列表。
  bool advanceMaster;

  /// 因为太长收起过多少条。界面上要如实说一句，不然人以为记录丢了。
  int dropped;

  /// 这场对话一共花了多少钱（元）。模型的价配不上就是 0。
  double costCny;

  /// 模型写的这一趟的计划。界面照着它画顶上那张卡。
  WorkPlan? plan;

  /// 计划做完时记录有多长。做完的那一张就停在那个位置，不再钉在顶上。
  int planAnchor;

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
        'tokensUsed': tokensUsed,
        if (systemPrompt.trim().isNotEmpty) 'systemPrompt': systemPrompt,
        if (profileId.isNotEmpty) 'profileId': profileId,
        if (advanceMaster) 'advanceMaster': true,
        if (dropped > 0) 'dropped': dropped,
        if (costCny > 0) 'cost': double.parse(costCny.toStringAsFixed(6)),
        if (plan != null) 'plan': plan!.toJson(),
        if (planAnchor > 0) 'planAnchor': planAnchor,
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
      tokensUsed: (json['tokensUsed'] as num?)?.toInt() ?? 0,
      systemPrompt: '${json['systemPrompt'] ?? ''}',
      profileId: '${json['profileId'] ?? ''}',
      advanceMaster: json['advanceMaster'] == true,
      dropped: (json['dropped'] as num?)?.toInt() ?? 0,
      costCny: (json['cost'] as num?)?.toDouble() ?? 0,
      plan: WorkPlan.fromJson(json['plan']),
      planAnchor: (json['planAnchor'] as num?)?.toInt() ?? 0,
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
      if (m.usage.total > 0) 'usage': usageToJson(m.usage),
    };

Map<String, Object?> usageToJson(LlmUsage u) => <String, Object?>{
      'prompt': u.prompt,
      'completion': u.completion,
      if (u.cached > 0) 'cached': u.cached,
    };

LlmUsage usageFromJson(Object? raw) {
  if (raw is! Map) return const LlmUsage();
  int read(String key) {
    final Object? v = raw[key];
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  return LlmUsage(
    prompt: read('prompt'),
    completion: read('completion'),
    cached: read('cached'),
  );
}

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
      return LlmMessage.assistant(text,
          calls: calls, usage: usageFromJson(json['usage']));
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
        final String text = await entity.readAsString();
        // 大文件解在另一个 isolate 里：几十兆的 JSON 在界面线程上解会把画面冻住。
        final Object? decoded = text.length > 400000
            ? await Isolate.run(() => jsonDecode(text))
            : jsonDecode(text);
        if (decoded is Map) {
          final Conversation c = Conversation.fromJson(Map<String, Object?>.from(decoded));
          if (c.id.isNotEmpty) {
            // 老版本留下的长记录，先收一次再放进来。
            c.dropped += trimTranscript(c.messages);
            _items.add(c);
          }
        }
      } catch (_) {
        // Skip a broken transcript instead of losing the rest.
      }
    }
  }

  Future<Conversation> create({
    required String title,
    String hostId = '',
    bool advanceMaster = false,
  }) async {
    final Conversation c = Conversation(
      id: 'c${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      title: title.trim().isEmpty ? '新对话' : title.trim(),
      hostId: advanceMaster ? '' : hostId,
      advanceMaster: advanceMaster,
    );
    _items.add(c);
    await save(c);
    return c;
  }

  Future<void> save(Conversation c) async {
    c.updatedAt = DateTime.now();
    dir.createSync(recursive: true);
    c.dropped += trimTranscript(c.messages);
    final Map<String, Object?> json = c.toJson();
    // 编码放在另一个 isolate 里，也不带缩进：缩进只是好看，长记录上要多占一半内存。
    final String text = await Isolate.run(() => jsonEncode(json));
    await File('${dir.path}/${c.id}.json').writeAsString(text);
  }

  Future<void> remove(String id) async {
    _items.removeWhere((Conversation c) => c.id == id);
    final File file = File('${dir.path}/$id.json');
    if (file.existsSync()) await file.delete();
  }

  File journalOf(Conversation c) => File('${dir.path}/${c.id}.journal.jsonl');
}
