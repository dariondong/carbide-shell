import '../core/models.dart';
import '../core/tools.dart';
import '../data/settings.dart';

/// `http_allow`：`http_request` 的域名允许列表，看一眼、加一条、删一条。
///
/// 加进去的域名连带它的子域名一起放行，下一次同样的地址就不用再问。
/// 清单存在设置里，和设置页那一格是同一份。
class HttpAllowTool extends Tool {
  HttpAllowTool(this.settings);

  final SettingsStore settings;

  @override
  String get name => 'http_allow';

  @override
  String get description =>
      'http_request 的允许域名清单。不给域名就是看一眼；给了域名就按 action 加进去或者删掉，'
      '默认是加。加进去的域名连带它的子域名一起放行。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'domain': <String, Object?>{
            'type': 'string',
            'description': '域名，比如 api.example.com；给整条网址也行，只取主机名',
          },
          'action': <String, Object?>{
            'type': 'string',
            'enum': <String>['list', 'add', 'remove'],
            'description': 'list 只看，add 加进去（默认），remove 删掉',
          },
        },
        'required': <String>[],
      };

  /// 看是读；加和删都改了设置，算写。
  @override
  ToolRisk classify(Map<String, Object?> args) {
    final String action = readString(args, 'action').trim().toLowerCase();
    final bool hasDomain = readString(args, 'domain').trim().isNotEmpty;
    if (action == 'list' || !hasDomain) return ToolRisk.read;
    return ToolRisk.write;
  }

  @override
  String summarize(Map<String, Object?> args) {
    final String action = readString(args, 'action').trim().toLowerCase();
    final String raw = readString(args, 'domain').trim();
    if (raw.isEmpty || action == 'list') return '看一眼 http_request 允许的域名';
    final String host = hostOf(raw);
    final String name = host.isEmpty ? raw : host;
    return action == 'remove'
        ? '把 $name 从 http_request 的允许列表删掉'
        : '把 $name 加进 http_request 的允许列表';
  }

  /// 从一句域名或者一整条网址里取出主机名。取不出来给空串。
  static String hostOf(String raw) {
    final String text = raw.trim().toLowerCase();
    if (text.isEmpty) return '';
    final Uri? uri = Uri.tryParse(text.contains('://') ? text : 'http://$text');
    String host = (uri?.host ?? '').trim();
    // 前缀里的 * 和点是「所有子域」的写法，存的时候不要。
    while (host.startsWith('*') || host.startsWith('.')) {
      host = host.substring(1);
    }
    if (host.isEmpty) return '';
    if (host == 'localhost') return host;
    final bool ok =
        RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$')
            .hasMatch(host);
    return ok ? host : '';
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String action = readString(args, 'action').trim().toLowerCase();
    final String raw = readString(args, 'domain').trim();
    final List<String> now = List<String>.of(settings.value.allowedDomains);

    if (raw.isEmpty || action == 'list') {
      if (now.isEmpty) {
        return const ToolOutcome.success(
            stdout: '允许列表现在是空的，http_request 一个域名都发不出去。');
      }
      final StringBuffer b = StringBuffer(
          'http_request 现在允许这些域名，连带子域名：\n');
      for (final String d in now) {
        b.writeln('- $d');
      }
      return ToolOutcome.success(stdout: b.toString().trimRight());
    }

    final String host = hostOf(raw);
    if (host.isEmpty) return ToolOutcome.failure('这不像个域名：$raw');

    if (action == 'remove') {
      final List<String> next = now.where((String d) => d != host).toList();
      if (next.length == now.length) {
        return ToolOutcome.success(stdout: '$host 本来就不在列表里。');
      }
      settings.value.allowedDomains = next;
      await settings.save();
      return ToolOutcome.success(
          stdout: '$host 删掉了，现在还有 ${next.length} 个域名。');
    }

    if (now.contains(host)) {
      return ToolOutcome.success(stdout: '$host 已经在列表里了，直接发就行。');
    }
    settings.value.allowedDomains = <String>[...now, host];
    await settings.save();
    return ToolOutcome.success(stdout: '$host 加进去了，现在一共 ${now.length + 1} 个域名。');
  }
}
