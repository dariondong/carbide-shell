import '../core/memory.dart';
import '../core/models.dart';
import '../core/tools.dart';

/// `memory`：长期记忆的整张清单，看、加、改、删。
///
/// `remember` 只会往里加；这一件才是改旧的。每一条带一个短 id，
/// 改和删都按 id 来，改完还是那一条，不新增。
class MemoryTool extends Tool {
  MemoryTool(this.memory);

  final MemoryStore memory;

  /// 一次最多念几条，够看清手上有什么。
  static const int _showMax = 40;

  @override
  String get name => 'memory';

  @override
  String get description =>
      '长期记忆的清单：list 看全部（带 id），add 加一条，update 按 id 改写，delete 按 id 删掉。'
      '记下来的会出现在你的系统提示里，下次开软件还在。'
      '要改一条旧的就用 update，不要重复 add 一条新的。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'action': <String, Object?>{
            'type': 'string',
            'enum': <String>['list', 'add', 'update', 'delete'],
            'description': '默认 list',
          },
          'id': <String, Object?>{
            'type': 'string',
            'description': 'update / delete 要的那一条，list 里每行开头那个',
          },
          'text': <String, Object?>{'type': 'string', 'description': '记的一句话'},
          'tag': <String, Object?>{
            'type': 'string',
            'description': '可选分类：偏好 / 主机 / 规则',
          },
        },
        'required': <String>[],
      };

  /// 看、加、改都不动别的，删掉一条算改。
  @override
  ToolRisk classify(Map<String, Object?> args) =>
      readString(args, 'action').trim().toLowerCase() == 'delete'
          ? ToolRisk.write
          : ToolRisk.read;

  @override
  String summarize(Map<String, Object?> args) {
    final String action = _actionOf(args);
    final String text = readString(args, 'text').trim();
    final String id = readString(args, 'id').trim();
    switch (action) {
      case 'add':
        return '记一笔：$text';
      case 'update':
        return '改写记忆 $id${text.isEmpty ? '' : '：$text'}';
      case 'delete':
        return '删掉记忆 $id';
      default:
        return '看长期记忆';
    }
  }

  static String _actionOf(Map<String, Object?> args) {
    final String action = readString(args, 'action').trim().toLowerCase();
    return const <String>['list', 'add', 'update', 'delete'].contains(action) ? action : 'list';
  }

  String _render() {
    if (memory.entries.isEmpty) return '长期记忆现在是空的。';
    final StringBuffer b = StringBuffer('长期记忆 ${memory.length} 条（新的在前）：\n');
    int shown = 0;
    for (final MemoryEntry e in memory.entries) {
      if (shown >= _showMax) break;
      b.writeln('- ${e.id}  ${e.tag.isEmpty ? '' : '[${e.tag}] '}${e.text}');
      shown += 1;
    }
    if (memory.length > shown) b.writeln('还有 ${memory.length - shown} 条没列。');
    return b.toString().trimRight();
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String action = _actionOf(args);
    final String text = readString(args, 'text').trim();
    final String tag = readString(args, 'tag').trim();
    final String id = readString(args, 'id').trim();

    switch (action) {
      case 'add':
        if (text.isEmpty) return const ToolOutcome.failure('要记什么写在 text 里。');
        final MemoryEntry added = await memory.add(text, tag: tag);
        return ToolOutcome.success(stdout: '记下了（${added.id}）。${_render()}');

      case 'update':
        if (id.isEmpty) return const ToolOutcome.failure('要改哪一条？id 在 list 里每行开头。');
        if (text.isEmpty && tag.isEmpty) {
          return const ToolOutcome.failure('text 和 tag 都是空的，没东西可改。');
        }
        final MemoryEntry? old = _find(id);
        if (old == null) {
          return ToolOutcome.failure('没有这一条：$id\n${_render()}');
        }
        await memory.update(
          old.id,
          text: text.isEmpty ? null : text,
          tag: tag.isEmpty ? null : tag,
        );
        return ToolOutcome.success(stdout: '改好了。${_render()}');

      case 'delete':
        if (id.isEmpty) return const ToolOutcome.failure('要删哪一条？id 在 list 里每行开头。');
        final MemoryEntry? gone = _find(id);
        if (gone == null) {
          return ToolOutcome.failure('没有这一条：$id\n${_render()}');
        }
        await memory.remove(gone.id);
        return ToolOutcome.success(stdout: '删掉了「${gone.text}」。现在 ${memory.length} 条。');

      default:
        return ToolOutcome.success(stdout: _render());
    }
  }

  /// 按 id 找，也认 id 的开头那一段，省得模型抄错一位就找不到。
  MemoryEntry? _find(String id) {
    for (final MemoryEntry e in memory.entries) {
      if (e.id == id) return e;
    }
    if (id.length < 6) return null;
    for (final MemoryEntry e in memory.entries) {
      if (e.id.startsWith(id)) return e;
    }
    return null;
  }
}
