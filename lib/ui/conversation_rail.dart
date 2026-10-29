import 'package:flutter/material.dart';

import '../core/conversation.dart';
import '../data/hosts.dart';
import '../data/hub.dart';
import '../services.dart';
import 'motion.dart';
import 'theme.dart';

/// 会话常驻在左边：宽屏时一直摆着，点哪一条右边就换成哪一场对话。
///
/// 窄屏用不着它，那一页还是整页的会话列表。
class ConversationRail extends StatelessWidget {
  const ConversationRail({
    super.key,
    required this.services,
    required this.hub,
    required this.currentId,
    required this.onOpen,
    required this.onNew,
    required this.onDelete,
  });

  final AppServices services;
  final SessionHub hub;

  /// 右边正在看的那一场，选中的那条会亮起来。
  final String currentId;
  final void Function(Conversation) onOpen;
  final VoidCallback onNew;
  final void Function(Conversation) onDelete;

  static const double width = 268;

  @override
  Widget build(BuildContext context) {
    final List<Conversation> list = services.conversations.all;
    return SizedBox(
      width: width,
      child: Column(
        children: <Widget>[
          Container(
            height: 56,
            padding: const EdgeInsets.fromLTRB(16, 0, 10, 0),
            child: Row(
              children: <Widget>[
                const Text('会话',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
                const SizedBox(width: 8),
                Text('${list.length}', style: C.monoSmall),
                const Spacer(),
                _newButton(),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: C.rule),
          Expanded(
            child: list.isEmpty
                ? _empty()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 10, 8, 14),
                    itemCount: list.length,
                    itemBuilder: (BuildContext context, int i) => FadeSlideIn(
                      delay: Motion.stagger * (i < 8 ? i : 8),
                      lift: 6,
                      child: _row(list[i]),
                    ),
                  ),
          ),
          _petFoot(),
        ],
      ),
    );
  }

  /// 栏底那一小块：没事的时候它就睡在那儿，有活在跑就抬起头。
  Widget _petFoot() {
    final PetMood mood = petMoodNow(
      running: hub.runningCount > 0,
      waiting: hub.waitingOnes.isNotEmpty,
    );
    final String note = switch (mood) {
      PetMood.working => '${hub.runningCount} 场在跑',
      PetMood.thinking => '等你点一下',
      PetMood.sleeping => '没事干，睡一会儿',
      PetMood.idle => '待机',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: C.rule)),
      ),
      child: Row(
        children: <Widget>[
          PetAvatar(size: 46, mood: mood),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(mood.label,
                    style: const TextStyle(fontSize: 12, color: C.ink, height: 1.4)),
                Text(note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: C.monoSmall.copyWith(fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _newButton() {
    return PressScale(
      onTap: onNew,
      scale: 0.92,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: C.blue,
          borderRadius: BorderRadius.circular(C.radiusSmall),
        ),
        child: const Icon(Icons.add, size: 17, color: Colors.white),
      ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('还没有对话',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.5)),
          const SizedBox(height: 6),
          const Text('一个对话管一台主机或者全部主机，记忆跟着它走。',
              style: TextStyle(fontSize: 12, height: 1.6, color: C.grey)),
        ],
      ),
    );
  }

  Widget _row(Conversation c) {
    final bool on = c.id == currentId;
    final bool waiting = hub.isWaiting(c.id);
    final bool busy = hub.isRunning(c.id);
    final HostEntry? host = c.multiHost ? null : services.hosts.byId(c.hostId);
    final String scope = c.multiHost
        ? (c.advanceMaster ? '全部主机 · AM' : '全部主机')
        : (host == null ? '主机已删除' : host.name);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onOpen(c),
          borderRadius: BorderRadius.circular(C.radiusSmall),
          child: AnimatedContainer(
            duration: Motion.swap,
            curve: Motion.curve,
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            decoration: BoxDecoration(
              color: on ? C.blueSoft : const Color(0x00000000),
              borderRadius: BorderRadius.circular(C.radiusSmall),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                _mark(on: on, busy: busy, waiting: waiting),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        c.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                          color: on ? C.blue : C.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${waiting ? '等你确认 · ' : busy ? '在跑 · ' : ''}$scope · ${_ago(c.updatedAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: C.monoSmall.copyWith(
                          fontSize: 10,
                          color: waiting || busy ? C.blue : C.grey2,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 26,
                  height: 26,
                  child: IconButton(
                    onPressed: () => onDelete(c),
                    icon: const Icon(Icons.close, size: 13, color: C.grey2),
                    splashRadius: 13,
                    constraints: const BoxConstraints.tightFor(width: 26, height: 26),
                    padding: EdgeInsets.zero,
                    tooltip: '删掉',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 左边这一点：在跑是转动的圈，等你确认是实心墨蓝，其余是一枚淡灰点。
  Widget _mark({required bool on, required bool busy, required bool waiting}) {
    if (busy || waiting) {
      return SizedBox(
        width: 8,
        height: 8,
        child: busy
            ? const CircularProgressIndicator(strokeWidth: 1.4, color: C.blue)
            : const DecoratedBox(
                decoration: BoxDecoration(color: C.blue, shape: BoxShape.circle),
              ),
      );
    }
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: on ? C.blue : C.rule2,
        shape: BoxShape.circle,
      ),
    );
  }

  static String _ago(DateTime at) {
    final Duration d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inHours < 1) return '${d.inMinutes} 分钟前';
    if (d.inDays < 1) return '${d.inHours} 小时前';
    return '${d.inDays} 天前';
  }
}
