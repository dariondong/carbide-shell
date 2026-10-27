import 'dart:io';

import 'package:carbide_shell/core/diff.dart';
import 'package:carbide_shell/core/models.dart';
import 'package:carbide_shell/data/hosts.dart';
import 'package:carbide_shell/data/secrets.dart';
import 'package:carbide_shell/data/snapshots.dart';
import 'package:carbide_shell/data/temp_files.dart';
import 'package:carbide_shell/tools/diff_tool.dart';
import 'package:carbide_shell/tools/ssh_tools.dart';
import 'package:flutter_test/flutter_test.dart';

const ToolContext _ctx = ToolContext(workspace: '/tmp', desktop: true);

void main() {
  group('unifiedDiff', () {
    const String a = 'a\nb\nc\nd\ne\n';
    const String b = 'a\nb\nC\nd\ne\n';

    test('改一行就只回那一行', () {
      final DiffResult d = unifiedDiff(a, b);
      expect(d.same, isFalse);
      expect(d.text.startsWith('--- a\n+++ b\n'), isTrue);
      expect(d.text, contains('\n-c\n'));
      expect(d.text, contains('\n+C\n'));
      expect(d.added, 1);
      expect(d.removed, 1);
    });

    test('一样的时候是空串，不给多余的字', () {
      final DiffResult d = unifiedDiff(a, a);
      expect(d.same, isTrue);
      expect(d.text, isEmpty);
    });

    test('相隔远的两处各给一块', () {
      final String many = List<String>.generate(30, (int i) => 'line $i').join('\n');
      final String changed = many
          .replaceAll('line 2\n', 'line 2 changed\n')
          .replaceAll('line 28', 'line 28 changed');
      final DiffResult d = unifiedDiff(many, changed, context: 1);
      expect(RegExp(r'^@@ ', multiLine: true).allMatches(d.text).length, 2);
      expect(d.text, contains(' line 1\n'));
      expect(d.text, isNot(contains(' line 10\n')));
    });

    test('上下文写 0 就只回变化的行', () {
      final DiffResult d = unifiedDiff(a, b, context: 0);
      expect(d.text, contains('@@'));
      final List<String> body = d.text
          .split('\n')
          .skip(2) // --- 和 +++ 两行头
          .where((String line) => line.isNotEmpty)
          .toList();
      expect(body.any((String line) => line.startsWith(' ')), isFalse, reason: body.join('|'));
      expect(body, contains('-c'));
      expect(body, contains('+C'));
    });

    test('一边是空的也认', () {
      final DiffResult d = unifiedDiff('', 'x\ny\n');
      expect(d.added, 2);
      expect(d.removed, 0);
      expect(d.text, contains('+x'));
    });

    test('两千行全改也不卡', () {
      final String big1 = List<String>.generate(2000, (int i) => 'x$i').join('\n');
      final String big2 = List<String>.generate(2000, (int i) => 'y$i').join('\n');
      final Stopwatch watch = Stopwatch()..start();
      final DiffResult d = unifiedDiff(big1, big2);
      watch.stop();
      expect(d.added, 2000);
      expect(d.removed, 2000);
      expect(watch.elapsedMilliseconds, lessThan(5000));
    });
  });

  group('SnapshotStore', () {
    late Directory dir;
    late SnapshotStore store;

    setUp(() {
      dir = Directory(
          '${Directory.systemTemp.path}/carbide_snap_${DateTime.now().microsecondsSinceEpoch}');
      store = SnapshotStore(dir);
    });

    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('存一份再按时间取回来', () async {
      final DateTime at = DateTime(2026, 10, 26, 12);
      await store.save('mgr', '/etc/x.conf', 'one\n', at: at);
      final List<Snapshot> all = store.list('mgr', '/etc/x.conf');
      expect(all.length, 1);
      expect(all.first.text, 'one\n');
      expect(all.first.at, at);
    });

    test('要找一天前的样，没有就说没有', () async {
      final DateTime now = DateTime(2026, 10, 27, 12);
      await store.save('mgr', '/etc/x.conf', 'fresh\n', at: now.subtract(const Duration(hours: 2)));
      expect(await store.older('mgr', '/etc/x.conf', const Duration(hours: 24), now: now), isNull);
      await store.save('mgr', '/etc/x.conf', 'old\n', at: now.subtract(const Duration(hours: 30)));
      final Snapshot? hit =
          await store.older('mgr', '/etc/x.conf', const Duration(hours: 24), now: now);
      expect(hit, isNotNull);
      expect(hit!.text, 'old\n');
    });

    test('多份满足条件时取最新的那份', () async {
      final DateTime now = DateTime(2026, 10, 27, 12);
      await store.save('mgr', '/e', 'd3\n', at: now.subtract(const Duration(hours: 72)));
      await store.save('mgr', '/e', 'd2\n', at: now.subtract(const Duration(hours: 48)));
      await store.save('mgr', '/e', 'fresh\n', at: now);
      final Snapshot? hit = await store.older('mgr', '/e', const Duration(hours: 24), now: now);
      expect(hit!.text, 'd2\n');
    });

    test('主机或路径不同就互不干扰', () async {
      await store.save('mgr', '/e', 'mgr\n');
      expect(store.list('hk', '/e'), isEmpty);
      expect(store.list('mgr', '/f'), isEmpty);
    });

    test('同一份只留最近几份，旧的自己删掉', () async {
      final DateTime now = DateTime(2026, 10, 27, 12);
      for (int i = 0; i < SnapshotStore.keep + 5; i += 1) {
        await store.save('mgr', '/e', 'v$i\n', at: now.add(Duration(minutes: i)));
      }
      expect(store.list('mgr', '/e').length, SnapshotStore.keep);
      expect(store.list('mgr', '/e').first.text, 'v${SnapshotStore.keep + 4}\n');
    });
  });

  group('remote_diff', () {
    late Directory dir;
    late RemoteDiffTool tool;
    late HostStore hosts;

    setUp(() {
      dir = Directory(
          '${Directory.systemTemp.path}/carbide_diff_${DateTime.now().microsecondsSinceEpoch}');
      final TempFiles files = TempFiles(dir);
      files.ensure();
      hosts = HostStore(File('${dir.path}/hosts.json'));
      tool = RemoteDiffTool(
        pool: SshPool(hosts: hosts, secrets: MemorySecretStore()),
        hosts: hosts,
        files: files,
      );
    });

    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('没给路径直接说', () async {
      final ToolOutcome out = await tool.run(<String, Object?>{}, _ctx);
      expect(out.ok, isFalse);
      expect(out.error, contains('a 和 b'));
    });

    test('主机列表是空的时候说没有这台，不去连', () async {
      final ToolOutcome out = await tool.run(<String, Object?>{
        'a': '/etc/x',
        'b': '/etc/y',
        'host_a': 'mgr',
      }, _ctx);
      expect(out.ok, isFalse);
      expect(out.error, contains('没有这台'));
    });

    test('审批卡上念得出比的是什么', () {
      expect(tool.summarize(<String, Object?>{'a': '/etc/a', 'b': '/etc/b'}), contains('/etc/a'));
    });
  });
}
