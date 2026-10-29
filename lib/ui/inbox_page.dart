import 'package:flutter/material.dart';

import '../data/mail.dart';
import 'components.dart';
import 'motion.dart';
import 'theme.dart';

/// 收件箱：最近几封，点开看一封。
///
/// 只读。发信、改地址那几件事都在设置 → 邮件里，这一页什么都不改，
/// 连「标记已读」都不动：服务器上那封信原来是什么样，看完还是什么样。
class InboxPage extends StatefulWidget {
  const InboxPage({super.key, required this.mail});

  final MailStore mail;

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  List<MailSummary> _list = const <MailSummary>[];
  bool _loading = false;
  bool _unreadOnly = false;
  String _note = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool? unreadOnly}) async {
    final bool only = unreadOnly ?? _unreadOnly;
    setState(() {
      _loading = true;
      _unreadOnly = only;
      _note = '';
    });
    try {
      final List<MailSummary> list =
          await widget.mail.inbox(count: 20, unreadOnly: only);
      if (!mounted) return;
      setState(() {
        _list = list;
        _loading = false;
      });
    } on ImapError catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _note = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _note = '$e';
      });
    }
  }

  Future<void> _openMail(MailSummary one) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MailMessagePage(mail: widget.mail, summary: one),
      ),
    );
    if (!mounted) return;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final bool ready = widget.mail.inboxReady;
    return Scaffold(
      backgroundColor: C.paper,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: C.card,
                border: Border(bottom: BorderSide(color: C.rule)),
              ),
              child: Row(
                children: <Widget>[
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.arrow_back, size: 19, color: C.ink),
                  ),
                  const Text('收件箱',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (ready)
                    TextButton(
                      onPressed: _loading ? null : () => _load(),
                      style: TextButton.styleFrom(
                        foregroundColor: C.blue,
                        minimumSize: const Size(0, 34),
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                      child: Text(_loading ? '正在拉…' : '刷新'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
                children: <Widget>[
                  if (!ready) ...<Widget>[
                    FadeSlideIn(
                      child: CardBox(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                        child: Text(
                          '还没配收信服务器：设置 → 邮件里把 IMAP 服务器和端口填上，'
                          '账号和授权码跟发信共用那两行。',
                          style: TextStyle(fontSize: 12.5, color: C.body, height: 1.7),
                        ),
                      ),
                    ),
                  ] else ...<Widget>[
                    FadeSlideIn(
                      child: CardBox(
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Text('${widget.mail.value.imap.user} · ${widget.mail.value.imapHost}',
                                    style: C.monoSmall),
                                const Spacer(),
                                _chip('只看未读', _unreadOnly,
                                    () => _load(unreadOnly: !_unreadOnly)),
                              ],
                            ),
                            if (_note.isNotEmpty) ...<Widget>[
                              const RuleLine(),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Text(_note,
                                    style: TextStyle(
                                        fontSize: 12, color: C.danger, height: 1.6)),
                              ),
                            ],
                            for (final MailSummary one in _list) ...<Widget>[
                              const RuleLine(),
                              _row(one),
                            ],
                            if (!_loading && _list.isEmpty && _note.isEmpty) ...<Widget>[
                              const RuleLine(),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                child: Text(
                                  _unreadOnly ? '没有没读过的信。' : '收件箱是空的。',
                                  style: TextStyle(fontSize: 12.5, color: C.grey),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    '只读：这一页不会把信标成已读，也不会动附件。AI 读到的正文同样算不可信内容。',
                    style: TextStyle(fontSize: 11, color: C.grey, height: 1.7),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? C.blue : C.card,
          borderRadius: BorderRadius.circular(C.radiusSmall),
          border: Border.all(color: on ? C.blue : C.rule2),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 11.5, color: on ? C.onAccent : C.ink)),
      ),
    );
  }

  Widget _row(MailSummary one) {
    return InkWell(
      onTap: () => _openMail(one),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(top: 6, right: 8),
              decoration: BoxDecoration(
                color: one.unread ? C.blue : const Color(0x00000000),
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    one.subject.isEmpty ? '（无主题）' : one.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: C.ink,
                      height: 1.4,
                      fontWeight: one.unread ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${one.fromName} · ${one.when}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: C.monoSmall,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: C.grey2),
          ],
        ),
      ),
    );
  }
}

/// 一封信用一整页：头几行加正文，长了下滑。
class MailMessagePage extends StatefulWidget {
  const MailMessagePage({super.key, required this.mail, required this.summary});

  final MailStore mail;
  final MailSummary summary;

  @override
  State<MailMessagePage> createState() => _MailMessagePageState();
}

class _MailMessagePageState extends State<MailMessagePage> {
  MailDetail? _detail;
  String _note = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _note = '';
    });
    try {
      final MailDetail detail = await widget.mail.read(widget.summary.uid);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } on ImapError catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _note = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _note = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final MailSummary head = _detail?.head ?? widget.summary;
    final String body = _detail?.body ?? '';
    return Scaffold(
      backgroundColor: C.paper,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: C.card,
                border: Border(bottom: BorderSide(color: C.rule)),
              ),
              child: Row(
                children: <Widget>[
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.arrow_back, size: 19, color: C.ink),
                  ),
                  Expanded(
                    child: Text(
                      head.subject.isEmpty ? '（无主题）' : head.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SelectionArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
                  children: <Widget>[
                    CardBox(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(head.from.isEmpty ? '（不知道谁）' : head.from,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: C.ink,
                                  fontWeight: FontWeight.w700,
                                  height: 1.4)),
                          const SizedBox(height: 4),
                          Text(head.when, style: C.monoSmall),
                          if ((_detail?.attachments ?? 0) > 0) ...<Widget>[
                            const SizedBox(height: 4),
                            Text('附件 ${_detail!.attachments} 个（没取）', style: C.monoSmall),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    CardBox(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                      child: _loading
                          ? Text('正在取这一封…',
                              style: TextStyle(fontSize: 12.5, color: C.grey, height: 1.6))
                          : Text(
                              _note.isNotEmpty
                                  ? _note
                                  : (body.isEmpty ? '（这封信没有能读的正文）' : body),
                              style: TextStyle(
                                fontSize: 13,
                                color: _note.isNotEmpty ? C.danger : C.body,
                                height: 1.65,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
