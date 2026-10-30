import 'package:carbide_shell/core/triggers.dart';
import 'package:carbide_shell/core/triggers_mention.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('这条是不是冲着我来的', () {
    final List<String> mine = <String>['Darion', 'BG7LZQ'];

    test('群里明确 @ 了我，算', () {
      final MessageTarget j = judgeTarget(
        title: 'Mc 26.2',
        text: '苏国佑 云浮新兴 BG7PGW: @Darion（BG7LZQ) BY7080SWL 我操你妈',
        myNames: mine,
      );
      expect(j.atMe, isTrue);
    });

    test('微信 @ 后面带全角空格，也算', () {
      final MessageTarget j = judgeTarget(
        title: 'Mc 26.2',
        text: '苏国佑: @　BG7LZQ 我操你妈',
        myNames: mine,
      );
      expect(j.atMe, isTrue);
    });

    test('群里没 @ 我，不算', () {
      final MessageTarget j = judgeTarget(
        title: 'Mc 26.2',
        text: '苏国佑 云浮新兴 BG7PGW: 我操你妈',
        myNames: mine,
      );
      expect(j.atMe, isFalse);
    });

    test('群里 @ 的是别人，不算', () {
      final MessageTarget j = judgeTarget(
        title: 'Mc 26.2',
        text: '苏国佑: @成-BG7PQQ 阳春 我操你妈',
        myNames: mine,
      );
      expect(j.atMe, isFalse);
    });

    test('只是提到我的名字，不是 @ 我，不算', () {
      final MessageTarget j = judgeTarget(
        title: 'Mc 26.2',
        text: '苏国佑: BG7LZQ 的电台坏了吗',
        myNames: mine,
      );
      expect(j.atMe, isFalse);
    });

    test('@全体成员，不算', () {
      final MessageTarget j = judgeTarget(
        title: 'Mc 26.2',
        text: '苏国佑: @全体成员 我操你妈',
        myNames: mine,
      );
      expect(j.atMe, isFalse);
    });

    test('私聊里单独发给我的，算', () {
      final MessageTarget j = judgeTarget(
        title: '苏国佑 云浮新兴 BG7PGW',
        text: '我操你妈',
        myNames: mine,
      );
      expect(j.atMe, isTrue);
    });

    test('我的名字是别人名字的一部分，不算', () {
      final MessageTarget j = judgeTarget(
        title: 'Mc 26.2',
        text: '苏国佑: @BG7LZQabc 我操你妈',
        myNames: mine,
      );
      expect(j.atMe, isFalse);
    });

    test('群名带方括号，当群处理', () {
      final MessageTarget j = judgeTarget(
        title: '#1002 特殊行动小组[表情]',
        text: '苏国佑: 我操你妈',
        myNames: mine,
      );
      expect(j.atMe, isFalse);
    });

    test('群名带版本号，当群处理', () {
      final MessageTarget j = judgeTarget(
        title: 'Mc 26.2',
        text: '苏国佑: 我操你妈',
        myNames: mine,
      );
      expect(j.atMe, isFalse);
    });

    test('昵称里带数字也不该误判成群', () {
      final MessageTarget j = judgeTarget(
        title: '苏国佑 云浮新兴 BG7PGW',
        text: '我操你妈',
        myNames: mine,
      );
      expect(j.atMe, isTrue);
    });

    test('真机上见过的群名，都该当群', () {
      for (final String g in <String>[
        '粤西无线电爱好者',
        'DPRS/APRS 技术应用专家群',
        'Mc 26.2',
        '#1002 特殊行动小组[表情]',
        '设备互联 全场景音乐服务',
      ]) {
        final MessageTarget j =
            judgeTarget(title: g, text: '苏国佑: 我操你妈', myNames: mine);
        expect(j.atMe, isFalse, reason: '群名「$g」没 @ 我就不该算');
      }
    });

    test('真机上见过的私聊昵称，都该当私聊', () {
      for (final String p in <String>[
        '苏国佑 云浮新兴 BG7PGW',
        '杨力源 104 电白',
        '成-BG7PQQ 阳春',
        '信宜BG7OPY',
      ]) {
        final MessageTarget j =
            judgeTarget(title: p, text: '我操你妈', myNames: mine);
        expect(j.atMe, isTrue, reason: '私聊「$p」该算冲着我');
      }
    });

    test('真机上@别人的，不该算我', () {
      final MessageTarget j = judgeTarget(
        title: '粤西无线电爱好者',
        text: '353 ＄风和自由&15706663304 BG7OSO 高州353: @信宜BG7OPY 台长讲四眼系坏的',
        myNames: mine,
      );
      expect(j.atMe, isFalse);
    });
  });

  group('关键词加对象一起看', () {
    test('不写「我是谁」，谁说了都算（老行为不变）', () {
      final Trigger t = Trigger(id: 't1', kind: TriggerKind.message, intent: '我操你妈');
      expect(messageMatches(t, 'Mc 26.2', '苏国佑: 我操你妈'), isTrue);
    });

    test('写清楚了「我是谁」，群里没 @ 我就不算', () {
      final Trigger t = Trigger(
        id: 't2',
        kind: TriggerKind.message,
        intent: '我操你妈',
        myNames: <String>['Darion', 'BG7LZQ'],
      );
      expect(messageMatches(t, 'Mc 26.2', '苏国佑: 我操你妈'), isFalse);
    });

    test('写清楚了「我是谁」，@ 了我才算', () {
      final Trigger t = Trigger(
        id: 't3',
        kind: TriggerKind.message,
        intent: '我操你妈',
        myNames: <String>['Darion', 'BG7LZQ'],
      );
      expect(
        messageMatches(t, 'Mc 26.2', '苏国佑: @Darion（BG7LZQ) BY7080SWL 我操你妈'),
        isTrue,
      );
    });

    test('关键词没碰上，@ 了我也不算', () {
      final Trigger t = Trigger(
        id: 't4',
        kind: TriggerKind.message,
        intent: '我操你妈',
        myNames: <String>['Darion', 'BG7LZQ'],
      );
      expect(messageMatches(t, 'Mc 26.2', '苏国佑: @Darion 你今天吃饭了吗'), isFalse);
    });
  });

  test('「我是谁」存得住，老文件默认没有', () {
    final Trigger on = Trigger(id: 't5', myNames: <String>['Darion', 'BG7LZQ']);
    expect(Trigger.fromJson(on.toJson()).myNames, <String>['Darion', 'BG7LZQ']);
    final Map<String, Object?> old = <String, Object?>{'id': 't6', 'kind': 'message'};
    expect(Trigger.fromJson(old).myNames, isEmpty);
  });
}
