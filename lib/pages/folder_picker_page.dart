import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../dsm/dsm_client.dart';
import '../dsm/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icon_tile.dart';
import '../widgets/feedback.dart';
import '../widgets/surfaces.dart';
import '../widgets/ui_kit.dart';

/// 选择一个 DSM 文件夹作为相册来源。
class FolderPickerPage extends StatefulWidget {
  final String initialPath;
  const FolderPickerPage({super.key, this.initialPath = '/'});

  @override
  State<FolderPickerPage> createState() => _FolderPickerPageState();
}

class _FolderPickerPageState extends State<FolderPickerPage> {
  late String _path = widget.initialPath;
  List<FileEntry> _folders = [];
  bool _loading = true;
  String? _error;

  bool get _atRoot => _path == '/' || _path.isEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final service = state.service;
    if (service == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      List<FileEntry> folders;
      if (_atRoot) {
        final shares = await service.shares();
        folders = shares.map((s) => FileEntry(name: s.name, path: s.path, isDir: true)).toList();
      } else {
        final entries = await service.files(_path);
        folders = entries.where((e) => e.isDir).toList();
      }
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _loading = false;
      });
    } on DsmException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _enter(FileEntry folder) async {
    setState(() => _path = folder.path);
    await _load();
  }

  Future<void> _up() async {
    if (_atRoot) {
      Navigator.of(context).pop();
      return;
    }
    final index = _path.lastIndexOf('/');
    setState(() => _path = index <= 0 ? '/' : _path.substring(0, index));
    await _load();
  }

  Future<void> _createFolder() async {
    final name = await showInputDialog(context, title: '新建文件夹', hint: '文件夹名称');
    if (name == null) return;
    try {
      await context.read<AppState>().service!.createFolder(_path, name);
      if (mounted) showToast(context, '已创建「$name」');
      await _load();
    } on DsmException catch (e) {
      if (mounted) showToast(context, e.message, icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PageScaffold(
        child: Column(
          children: [
            DetailHeader(
              title: '选择相册目录',
              subtitle: _atRoot ? '选择一个共享文件夹' : _path,
              onBack: _up,
              actions: [
                CircleIconButton(icon: Icons.create_new_folder_outlined, onTap: _createFolder, size: 20),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _atRoot
                      ? null
                      : () => Navigator.of(context).pop(_path),
                  child: const Text('选择'),
                ),
              ],
            ),
            if (!_atRoot)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
                child: Row(
                  children: [
                    Icon(Icons.folder_open_rounded, size: 16, color: c.primary),
                    const SizedBox(width: 6),
                    Expanded(child: Text(_path, style: context.texts.labelSmall?.copyWith(color: c.textTertiary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
                  : _error != null
                      ? Center(child: EmptyHint(icon: Icons.cloud_off_rounded, title: '无法读取目录', subtitle: _error, action: FilledButton(onPressed: _load, child: const Text('重试'))))
                      : _folders.isEmpty
                          ? Center(
                              child: EmptyHint(
                                icon: Icons.folder_open_rounded,
                                title: '没有子文件夹',
                                subtitle: _atRoot ? '没有可用的共享文件夹' : '可以点击右上角新建文件夹',
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
                              itemCount: _folders.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final folder = _folders[index];
                                return SoftCard(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  radius: 18,
                                  onTap: () => _enter(folder),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(colors: [Color(0xFF6FB6FF), Color(0xFF2F7CFF)]),
                                          borderRadius: BorderRadius.circular(13),
                                        ),
                                        child: const Icon(Icons.folder_rounded, size: 20, color: Colors.white),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(child: Text(folder.name, style: context.texts.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                      Icon(Icons.chevron_right_rounded, size: 18, color: c.textTertiary),
                                    ],
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
