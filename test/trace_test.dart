import 'package:carbide_shell/core/trace.dart';
import 'package:flutter_test/flutter_test.dart';

const String _journal = '''
{"at":"2026-10-26T02:00:00.000Z","event":"user","text":"看看磁盘"}
{"at":"2026-10-26T02:00:01.000Z","event":"llm","step":1,"prompt":1200,"cached":900,"out":80}
{"at":"2026-10-26T02:00:02.000Z","event":"tool","name":"ssh_exec","args":{"command":"df -h"},"summary":"在 web-01 上跑 df -h","verdict":"allow"}
{"at":"2026-10-26T02:00:03.000Z","event":"result","name":"ssh_exec","ok":true,"ms":420,"text":"/dev/sda1 92%"}
{"at":"2026-10-26T02:00:04.000Z","event":"llm","step":2,"prompt":1500,"cached":1100,"out":60}
{"at":"2026-10-26T02:00:05.000Z","event":"tool","name":"ask","args":{"note":"要不要清一下"},"summary":"问你一句","verdict":"ask"}
{"at":"2026-10-26T02:00:06.000Z","event":"final","text":"磁盘 92%，要不要清"}
''';

void main() {
  group('读工具轨迹', () {
    test('一轮里的事件按顺序摊开', () {
      final List<TraceEntry> list = parseJournal(_journal);
      expect(list.length, 6);
      expect(list.first.kind, TraceKind.turn);
      expect(list.first.turn, 1);
      expect(list.first.text, '看看磁盘');
      expect(list[1].kind, TraceKind.llm);
      expect(list[1].step, 1);
      expect(list[1].prompt, 1200);
      expect(list[1].cached, 900);
      expect(list[1].total, 1280);
      expect(list.last.kind, TraceKind.note);
      expect(list.last.text, contains('92%'));
    });

    test('工具和它的结果配成一条', () {
      final List<TraceEntry> tools =
          parseJournal(_journal).where((TraceEntry t) => t.isTool).toList();
      expect(tools.length, 2);
      final TraceEntry run = tools.first;
      expect(run.name, 'ssh_exec');
      expect(run.argText, 'df -h');
      expect(run.hasResult, isTrue);
      expect(run.ok, isTrue);
      expect(run.ms, 420);
      expect(run.output, contains('92%'));
      expect(run.verdictText, isEmpty);
    });

    test('没有结果的工具就还挂在那儿', () {
      final List<TraceEntry> tools =
          parseJournal(_journal).where((TraceEntry t) => t.isTool).toList();
      expect(tools[1].hasResult, isFalse);
      expect(tools[1].argText, '要不要清一下');
      expect(tools[1].verdictText, '问过你才跑');
    });

    test('拦下的那种也说得出原因', () {
      final List<TraceEntry> list = parseJournal(
          '{"event":"tool","name":"ssh_exec","args":{"command":"rm -rf /"},'
          '"summary":"rm -rf /","verdict":"deny"}');
      expect(list.single.verdictText, '被危险规则拦下');
    });

    test('坏行和认不出的事件跳过，不整份丢', () {
      final List<TraceEntry> list = parseJournal('''
破掉的一行
{"at":"2026-10-26T02:00:00.000Z","event":"weird","text":"看不懂"}
{"at":"2026-10-26T02:00:01.000Z","event":"user","text":"还在"}
''');
      expect(list.length, 1);
      expect(list.single.kind, TraceKind.turn);
      expect(list.single.text, '还在');
    });

    test('空日志给空表', () {
      expect(parseJournal(''), isEmpty);
    });

    test('结果先到也不会丢', () {
      final List<TraceEntry> list = parseJournal(
          '{"event":"result","name":"clock","ok":false,"ms":3,"text":"读不到"}');
      expect(list.single.isTool, isTrue);
      expect(list.single.ok, isFalse);
      expect(list.single.output, '读不到');
    });
  });
}
