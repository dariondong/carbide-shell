import 'package:carbide_shell/data/activity.dart';
import 'package:flutter_test/flutter_test.dart';

/// 记下通知那边收到过什么，不真去碰通道。
class _FakeSink implements ActivitySink {
  _FakeSink({this.visible = true});

  @override
  bool visible;

  final List<String> calls = <String>[];

  String lastState = '';
  bool lastResidual = false;
  String lastText = '';

  @override
  Future<void> begin(
    String text, {
    required String style,
    required List<String> lines,
    required String state,
  }) async {
    lastText = text;
    lastState = state;
    calls.add('begin:$state');
  }

  @override
  Future<void> update(
    String text, {
    required List<String> lines,
    required String state,
  }) async {
    lastText = text;
    lastState = state;
    calls.add('update:$state');
  }

  @override
  Future<void> complete(
    String text, {
    required String style,
    required List<String> lines,
    required bool residual,
  }) async {
    lastText = text;
    lastResidual = residual;
    calls.add('complete:$residual');
  }
}

void main() {
  group('通知上的三种状态', () {
    test('跑起来先说 run，换一句话还是 run', () async {
      final _FakeSink sink = _FakeSink();
      final ActivityBoard board = ActivityBoard(sink: sink);
      board.note('c:a', '第一条 · 开跑');
      await Future<void>.delayed(Duration.zero);
      expect(sink.calls, <String>['begin:run']);
      expect(sink.lastText, '第一条 · 开跑');

      board.note('c:a', '第一条 · 第 3/12 步 · 执行命令');
      await Future<void>.delayed(Duration.zero);
      expect(sink.calls.last, 'update:run');
    });

    test('停下等人批准，短字换 wait', () async {
      final _FakeSink sink = _FakeSink();
      final ActivityBoard board = ActivityBoard(sink: sink);
      board.note('c:a', '第一条 · 第 3/12 步 · 执行命令');
      board.note('c:a', '第一条 · 第 3/12 步 · 等你确认', state: 'wait');
      await Future<void>.delayed(Duration.zero);
      expect(board.phase, 'wait');
      expect(sink.calls.last, 'update:wait');
    });

    test('批准完继续跑，回到 run', () async {
      final _FakeSink sink = _FakeSink();
      final ActivityBoard board = ActivityBoard(sink: sink);
      board.note('c:a', '第一条 · 等你确认', state: 'wait');
      board.note('c:a', '第一条 · 第 4/12 步 · 执行命令');
      await Future<void>.delayed(Duration.zero);
      expect(board.phase, 'run');
      expect(sink.calls.last, 'update:run');
    });

    test('两件事里有一件在等人批准，整条就说 wait', () async {
      final _FakeSink sink = _FakeSink();
      final ActivityBoard board = ActivityBoard(sink: sink);
      board.note('c:a', '第一条 · 执行命令');
      board.note('t:1', '巡检 · 等你确认', state: 'wait');
      await Future<void>.delayed(Duration.zero);
      expect(board.count, 2);
      expect(board.phase, 'wait');
      expect(sink.calls.last, 'update:wait');
    });

    test('全做完时人就在应用里：换成已完成，不留残留那条', () async {
      final _FakeSink sink = _FakeSink(visible: true);
      final ActivityBoard board = ActivityBoard(sink: sink);
      board.note('c:a', '第一条 · 开跑');
      board.done('c:a', summary: '第一条 · 做完了');
      await Future<void>.delayed(Duration.zero);
      expect(sink.calls.last, 'complete:false');
      expect(sink.lastResidual, isFalse);
      expect(sink.lastText, '第一条 · 做完了');
    });

    test('全做完时人不在应用里：岛上照旧亮一下，完了留一条能点回来的', () async {
      final _FakeSink sink = _FakeSink(visible: false);
      final ActivityBoard board = ActivityBoard(sink: sink);
      board.note('c:a', '第一条 · 开跑');
      board.done('c:a', summary: '第一条 · 做完了');
      await Future<void>.delayed(Duration.zero);
      expect(sink.calls.last, 'complete:true');
      expect(sink.lastResidual, isTrue);
    });

    test('没写结果也要有一句话，不能是空的', () async {
      final _FakeSink sink = _FakeSink(visible: true);
      final ActivityBoard board = ActivityBoard(sink: sink);
      board.note('c:a', '第一条 · 开跑');
      board.done('c:a');
      await Future<void>.delayed(Duration.zero);
      expect(sink.lastText, '已完成');
    });

    test('状态跟着那件事一起收掉，别留给下一轮', () async {
      final _FakeSink sink = _FakeSink();
      final ActivityBoard board = ActivityBoard(sink: sink);
      board.note('c:a', '第一条 · 等你确认', state: 'wait');
      board.done('c:a');
      expect(board.phase, 'run');
      expect(board.any, isFalse);
    });
  });
}
