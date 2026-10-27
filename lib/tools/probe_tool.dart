import '../core/models.dart';
import '../core/tcp_probe.dart';
import '../core/tools.dart';

/// `http_probe`：只做一次 TCP 握手，回答「这个端口从外面通不通」。
///
/// 域名白名单拦的是 HTTP 请求，握手不经过它，所以这是唯一能在被拦的时候
/// 还说得清话的办法。只回通 / 不通 / 超时，不回内容。
class ProbeTool extends Tool {
  ProbeTool();

  @override
  String get name => 'http_probe';

  @override
  String get description =>
      '测一个地址的端口通不通：只做 TCP 握手，不发 HTTP、不取内容，所以不受域名白名单影响。'
      '地址可以是域名、IPv4、IPv6 字面量（方括号可选），端口 1-65535。'
      '只回答通 / 不通 / 超时和握手花了多久。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'host': <String, Object?>{
            'type': 'string',
            'description': '域名或 IP，比如 andymax.dpdns.org、8.138.199.11、::1',
          },
          'port': <String, Object?>{'type': 'integer', 'description': '端口，1-65535'},
          'timeout_seconds': <String, Object?>{
            'type': 'integer',
            'description': '等多久算超时，默认 5，最多 20',
          },
        },
        'required': <String>['host', 'port'],
      };

  /// 只握手，不改任何东西。
  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.read;

  @override
  String summarize(Map<String, Object?> args) {
    final String host = readString(args, 'host').trim();
    final int port = readInt(args, 'port');
    return '握手 $host:$port';
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String host = readString(args, 'host').trim();
    final int port = readInt(args, 'port');
    if (host.isEmpty) return const ToolOutcome.failure('要给一个 host。');
    int wait = readInt(args, 'timeout_seconds', fallback: 5);
    if (wait < 1) wait = 1;
    if (wait > 20) wait = 20;
    final TcpProbe probe = await probeTcp(
      host,
      port,
      timeout: Duration(seconds: wait),
    );
    if (probe.reachable) {
      return ToolOutcome.success(
        stdout: '通：$host:$port 握手 ${probe.ms} ms。',
        meta: <String, Object?>{
          'reachable': true,
          'latency_ms': probe.ms,
          'address': probe.address,
        },
      );
    }
    return ToolOutcome.success(
      stdout: '不通：$host:$port ${probe.error}（等了 ${probe.ms} ms）。',
      meta: <String, Object?>{
        'reachable': false,
        'latency_ms': probe.ms,
        'address': probe.address,
        'error': probe.error,
      },
    );
  }
}
