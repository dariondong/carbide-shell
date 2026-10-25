import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/hosts.dart';
import '../data/temp_files.dart';
import '../tools/ssh_tools.dart';
import '../tools/temp_tools.dart';
import 'components.dart';
import 'motion.dart';
import 'theme.dart';

/// 临时文件区。模型写进来的、你自己加进来的都在这儿，一个文件传到主机上只要点两下。
class TempFilesPage extends StatefulWidget {
  const TempFilesPage({
    super.key,
    required this.files,
    required this.hosts,
    required this.pool,
  });

  final TempFiles files;
  final HostStore hosts;
  final SshPool pool;

  @override
  State<TempFilesPage> createState() => _TempFilesPageState();
}

class _TempFilesPageState extends State<TempFilesPage> {
  List<TempFile> _items = <TempFile>[];

  @override
  void initState() {
    super.initState();
    _items = widget.files.list();
  }

  void _load() {
    if (!mounted) return;
    setState(() => _items = widget.files.list());
  }

  int get _total {
    int sum = 0;
    for (final TempFile f in _items) {
      sum += f.size;
    }
    return sum;
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _add() async {
    final FilePickerResult? picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    int added = 0;
    for (final PlatformFile f in picked.files) {
      final List<int>? bytes = f.bytes;
      if (bytes == null) continue;
      try {
        await widget.files.save(f.name, bytes);
        added += 1;
      } catch (e) {
        _toast('${f.name} 没进来：$e');
      }
    }
    _load();
    if (added > 0) _toast('加进来 $added 个文件。');
  }

  /// 删掉能撤回：字节先留在手里，撤销时按原路径写回去。
  Future<void> _remove(TempFile f) async {
    final File? local = widget.files.fileOf(f.path);
    List<int>? keep;
    if (local != null && local.existsSync() && f.size <= TempFiles.maxBytes) {
      keep = await local.readAsBytes();
    }
    final bool ok = await widget.files.remove(f.path);
    if (!ok) {
      _toast('这个文件已经不在了。');
      _load();
      return;
    }
    _load();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('删掉了 ${f.name}'),
        action: keep == null
            ? null
            : SnackBarAction(
                label: '撤销',
                textColor: C.card,
                onPressed: () async {
                  await widget.files.put(f.path, keep!);
                  _load();
                },
              ),
      ),
    );
  }

  Future<void> _clearAll() async {
    if (_items.isEmpty) return;
    final bool? ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (BuildContext ctx) => SheetCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SheetHead(
              title: '清空临时文件区',
              note: '${_items.length} 个文件 · ${tempSize(_total)}',
            ),
            const SizedBox(height: 14),
            const Text('这一块里的文件都会删掉，删完从服务器那头找不回来。',
                style: TextStyle(fontSize: 12.5, height: 1.55, color: C.grey)),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: SquareButton(
                    label: '留着',
                    tone: 'ink',
                    onPressed: () => Navigator.of(ctx).pop(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SquareButton(
                    label: '清空',
                    filled: true,
                    onPressed: () => Navigator.of(ctx).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await widget.files.clear();
    _load();
    _toast('清空了。');
  }

  Future<void> _preview(TempFile f) async {
    if (f.isImage) {
      final File? local = widget.files.fileOf(f.path);
      if (local == null || !local.existsSync()) {
        _toast('这个文件已经不在了。');
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (BuildContext ctx) => Dialog(
          backgroundColor: C.paper,
          insetPadding: const EdgeInsets.all(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(f.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: C.monoSmall.copyWith(color: C.ink)),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(),
                      behavior: HitTestBehavior.opaque,
                      child: const SizedBox(
                        width: 30,
                        height: 30,
                        child: Icon(Icons.close, size: 17, color: C.grey),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: InteractiveViewer(
                    maxScale: 4,
                    child: Image.file(local),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    final String? text = await widget.files.readText(f.path);
    if (!mounted) return;
    if (text == null) {
      _toast('${f.name} 是二进制文件，内容读不出来，只能传出去。');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (BuildContext ctx) => SheetCard(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.68,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SheetHead(title: f.name, note: f.path),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: C.paper2,
                    borderRadius: BorderRadius.circular(C.radiusSmall),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      text.isEmpty ? '（空文件）' : text,
                      style: C.mono.copyWith(fontSize: 11.5, height: 1.6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _upload(TempFile f) async {
    if (widget.hosts.hosts.isEmpty) {
      _toast('还没有主机，先在主机页加一台。');
      return;
    }
    final String? done = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (BuildContext ctx) => _UploadSheet(
        item: f,
        files: widget.files,
        hosts: widget.hosts,
        pool: widget.pool,
      ),
    );
    if (done == null || done.isEmpty) return;
    _toast('传到了 $done');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.paper,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Container(
              height: 56,
              padding: const EdgeInsets.fromLTRB(6, 0, 10, 0),
              decoration: const BoxDecoration(
                color: C.card,
                border: Border(bottom: BorderSide(color: C.rule)),
              ),
              child: Row(
                children: <Widget>[
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, size: 19, color: C.ink),
                  ),
                  const Text('临时文件',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Text('${_items.length} 个 · ${tempSize(_total)}', style: C.monoSmall),
                  const Spacer(),
                  GestureDetector(
                    onTap: _add,
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: C.blue,
                        borderRadius: BorderRadius.circular(C.radiusSmall),
                      ),
                      child: const Icon(Icons.add, size: 17, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _items.isEmpty
                  ? _empty()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                      children: <Widget>[
                        FadeSlideIn(
                          child: CardBox(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: <Widget>[
                                for (int i = 0; i < _items.length; i += 1) ...<Widget>[
                                  if (i > 0) const RuleLine(),
                                  _row(_items[i]),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Center(
                          child: TextButton(
                            onPressed: _clearAll,
                            style: TextButton.styleFrom(
                              foregroundColor: C.grey,
                              textStyle: const TextStyle(fontSize: 12.5),
                            ),
                            child: const Text('清空临时文件'),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('这里还没有文件',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.4)),
          const SizedBox(height: 8),
          const Text(
            '模型在这里写文件，你也可以把手机上的文件加进来。写好从这里传到服务器。',
            style: C.answer,
          ),
          const SizedBox(height: 18),
          SquareButton(label: '加一个文件', filled: true, onPressed: _add),
        ],
      ),
    );
  }

  Widget _row(TempFile f) {
    return InkWell(
      onTap: () => _preview(f),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: C.paper2,
                borderRadius: BorderRadius.circular(C.radiusSmall),
              ),
              child: Icon(_icon(f), size: 16, color: C.grey),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(f.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: C.ink)),
                  const SizedBox(height: 2),
                  Text('${tempSize(f.size)} · ${_when(f.modified)}', style: C.monoSmall),
                ],
              ),
            ),
            _iconButton(Icons.cloud_upload_outlined, '传到服务器', () => _upload(f)),
            _iconButton(Icons.delete_outline, '删除', () => _remove(f)),
          ],
        ),
      ),
    );
  }

  Widget _iconButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 17, color: C.grey),
        ),
      ),
    );
  }

  IconData _icon(TempFile f) {
    if (f.isImage) return Icons.image_outlined;
    if (f.isText) return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }

  static String _when(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    final DateTime local = t.toLocal();
    return '${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}

/// 传到服务器。主机一条条点，路径先填好再改。
class _UploadSheet extends StatefulWidget {
  const _UploadSheet({
    required this.item,
    required this.files,
    required this.hosts,
    required this.pool,
  });

  final TempFile item;
  final TempFiles files;
  final HostStore hosts;
  final SshPool pool;

  @override
  State<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends State<_UploadSheet> {
  late final TextEditingController _path =
      TextEditingController(text: '/tmp/${widget.item.name}');
  String _hostId = '';
  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    if (widget.hosts.hosts.length == 1) _hostId = widget.hosts.hosts.first.id;
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_busy) return;
    final HostEntry? entry = widget.hosts.byId(_hostId);
    if (entry == null) {
      setState(() => _error = '先点一下主机。');
      return;
    }
    final File? local = widget.files.fileOf(widget.item.path);
    if (local == null || !local.existsSync()) {
      setState(() => _error = '这个文件已经不在了。');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final TempUpload done =
          await sftpUpload(widget.pool, entry, local, _path.text);
      if (!mounted) return;
      Navigator.of(context).pop('${done.host}:${done.path}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '传不上去：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<HostEntry> hosts = widget.hosts.hosts;
    final HostEntry? picked = widget.hosts.byId(_hostId);
    return SheetCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SheetHead(
            title: '传到服务器',
            note: '${widget.item.path} · ${tempSize(widget.item.size)}',
          ),
          const SizedBox(height: 16),
          const SectionLabel('主机'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final HostEntry h in hosts)
                _hostChip(h, h.id == _hostId),
            ],
          ),
          const SizedBox(height: 8),
          Text(picked == null ? '还没选主机' : picked.host,
              style: C.monoSmall.copyWith(color: picked == null ? C.grey2 : C.grey)),
          const SizedBox(height: 16),
          const SectionLabel('远端路径'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: C.paper2,
              borderRadius: BorderRadius.circular(C.radiusSmall),
            ),
            child: TextField(
              controller: _path,
              enabled: !_busy,
              style: C.mono.copyWith(fontSize: 13),
              decoration: const InputDecoration(hintText: '/tmp/文件名'),
            ),
          ),
          if (_error.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(_error,
                style: const TextStyle(
                    fontSize: 12, height: 1.5, color: Color(0xFFD7443E))),
          ],
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              Expanded(
                child: SquareButton(
                  label: '取消',
                  tone: 'ink',
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SquareButton(
                  label: _busy ? '正在传' : '上传',
                  filled: true,
                  onPressed: _busy ? null : _run,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _hostChip(HostEntry h, bool on) {
    return GestureDetector(
      onTap: _busy ? null : () => setState(() => _hostId = h.id),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? C.blue : C.card,
          borderRadius: BorderRadius.circular(C.radiusSmall),
          border: Border.all(color: on ? C.blue : C.rule2),
        ),
        child: Text(
          h.name,
          style: TextStyle(
            fontSize: 12,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
            color: on ? Colors.white : C.ink,
          ),
        ),
      ),
    );
  }
}
