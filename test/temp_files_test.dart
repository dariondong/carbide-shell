import 'dart:convert';
import 'dart:io';

import 'package:carbide_shell/data/temp_files.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late TempFiles files;

  setUp(() {
    dir = Directory(
        '${Directory.systemTemp.path}/carbide_temp_${DateTime.now().microsecondsSinceEpoch}');
    files = TempFiles(dir);
    files.ensure();
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('名字只留文件名，别的字符换掉', () {
    expect(TempFiles.cleanName('a/b/c.txt'), 'c.txt');
    expect(TempFiles.cleanName('../evil'), 'evil');
    expect(TempFiles.cleanName('   '), 'file');
    expect(TempFiles.cleanName('my file.md'), 'my_file.md');
    expect(TempFiles.cleanName('报告 一.md'), '报告_一.md');
  });

  test('路径锁在临时文件区里面', () {
    expect(files.fileOf('a.txt')!.path, '${dir.path}/a.txt');
    expect(files.fileOf('reports/a.md')!.path, '${dir.path}/reports/a.md');
    expect(files.fileOf('../x'), isNull);
    expect(files.fileOf('a/../../x'), isNull);
    expect(files.fileOf('/etc/passwd'), isNull);
    expect(files.fileOf('  '), isNull);
  });

  test('写进去再读回来', () async {
    final TempFile one = await files.saveText('reports/a.md', '# 标题\n正文');
    expect(one.path, 'reports/a.md');
    expect(one.size, utf8.encode('# 标题\n正文').length);
    expect(await files.readText('reports/a.md'), '# 标题\n正文');
    expect(await files.readText('nope.md'), isNull);
  });

  test('同一个名字再写一次就地覆盖', () async {
    await files.saveText('a.md', '第一份');
    final TempFile again = await files.saveText('a.md', '第二份');
    expect(again.path, 'a.md');
    expect(await files.readText('a.md'), '第二份');
  });

  test('用户加进来的文件不覆盖旧的', () async {
    final TempFile one = await files.save('报告.md', utf8.encode('一'));
    final TempFile two = await files.save('报告.md', utf8.encode('二'));
    expect(one.path, '报告.md');
    expect(two.path, '报告-2.md');
    expect(files.list().length, 2);
  });

  test('二进制不当文本读', () async {
    await File('${dir.path}/bin.dat').writeAsBytes(<int>[0, 1, 2, 3]);
    expect(await files.readText('bin.dat'), isNull);
  });

  test('超过上限不给存', () async {
    await expectLater(
      files.save('big.bin', List<int>.filled(TempFiles.maxBytes + 1, 7)),
      throwsA(isA<StateError>()),
    );
  });

  test('删掉能按原路径写回来，清空就把这一块腾空', () async {
    await files.saveText('x.txt', 'x');
    expect(await files.remove('x.txt'), isTrue);
    expect(await files.remove('x.txt'), isFalse);
    await files.put('x.txt', utf8.encode('x'));
    expect(await files.readText('x.txt'), 'x');
    expect(files.totalBytes(), 1);
    await files.clear();
    expect(files.list(), isEmpty);
  });
}
