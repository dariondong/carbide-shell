/// 只做 TCP 握手的一次连通性测试。纯 Dart，不发任何应用层数据。
///
/// 用途：想知道「这个端口从外面通不通」，又不想因为域名白名单被挡住。
/// 只做握手就够回答这个问题，所以这里一个字节的请求都不发，也不回内容。
library;

import 'dart:async';
import 'dart:io';

class TcpProbe {
  const TcpProbe({
    required this.reachable,
    this.ms = 0,
    this.error = '',
    this.address = '',
  });

  final bool reachable;

  /// 握手花了多少毫秒。不通时是从开始到放弃的时间。
  final int ms;

  /// 不通的原因，通了就空着。
  final String error;

  /// 域名最后落到哪个地址。裸 IP 就跟输入一样。
  final String address;

  bool get timedOut => error.contains('超时');
}

/// 连一下 [host]:[port]，看看握手成不成。
///
/// [host] 可以是域名、IPv4，也可以是带方括号的 IPv6（`[2409:8a55::1]`）。
Future<TcpProbe> probeTcp(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final String target = _bareHost(host);
  if (target.isEmpty) {
    return const TcpProbe(reachable: false, error: '没给地址');
  }
  if (port < 1 || port > 65535) {
    return TcpProbe(reachable: false, error: '端口 $port 不在 1-65535 里');
  }
  final Stopwatch watch = Stopwatch()..start();
  Socket? socket;
  try {
    socket = await Socket.connect(target, port, timeout: timeout);
    watch.stop();
    return TcpProbe(
      reachable: true,
      ms: watch.elapsedMilliseconds,
      address: socket.remoteAddress.address,
    );
  } on TimeoutException {
    watch.stop();
    return TcpProbe(
      reachable: false,
      ms: watch.elapsedMilliseconds,
      error: '超时（${timeout.inSeconds} 秒没握上手）',
    );
  } on SocketException catch (e) {
    watch.stop();
    final String detail = e.osError?.message ?? e.message;
    return TcpProbe(
      reachable: false,
      ms: watch.elapsedMilliseconds,
      error: detail.isEmpty ? '连不上' : detail,
    );
  } catch (e) {
    watch.stop();
    return TcpProbe(
      reachable: false,
      ms: watch.elapsedMilliseconds,
      error: '$e'.replaceFirst('Exception: ', ''),
    );
  } finally {
    try {
      socket?.destroy();
    } catch (_) {
      // 连不上时 socket 是空的，连上了也已经关了。
    }
  }
}

/// 去掉 IPv6 的方括号，顺手把两头的空白切掉。
String _bareHost(String host) {
  String text = host.trim();
  if (text.startsWith('[') && text.endsWith(']')) {
    text = text.substring(1, text.length - 1);
  }
  return text;
}
