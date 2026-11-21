import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../dsm/dsm_client.dart';
import '../dsm/dsm_service.dart';
import '../dsm/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/feedback.dart';
import '../widgets/file_visual.dart';
import '../widgets/nav_bar.dart';
import '../widgets/surfaces.dart';
import '../widgets/ui_kit.dart';
import 'files_browser_page.dart';
import 'storage_page.dart';

class FilesPage extends StatefulWidget {
  final bool active;
  const FilesPage({super.key, this.active = true});

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  List<ShareInfo> _shares = [];
  List<FileEntry> _recent = [];
  bool _loading = true;
  String? _error;
  bool _requested = false;
  Map<String, int> _folderCounts = {};
  Map<String, int> _fileCounts = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant FilesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    final service = context.read<AppState>().service;
    if (service == null) return;
    if (!silent || !_requested) setState(() => _loading = true);
    _requested = true;
    try {
      final shares = await service.shares();
      final entriesLists = await Future.wait(shares.map((share) => _safeFiles(service, share.path)));
      final recent = <FileEntry>[];
      final folderCounts = <String, int>{};
      final fileCounts = <String, int>{};
      for (var i = 0; i < shares.length; i++) {
        final entries = entriesLists[i];
        folderCounts[shares[i].path] = entries.where((e) => e.isDir).length;
        fileCounts[shares[i].path] = entries.where((e) => !e.isDir).length;
        recent.addAll(entries.where((e) => !e.isDir));
      }
      recent.sort((a, b) => (b.mtime ?? DateTime(0)).compareTo(a.mtime ?? DateTime(0)));
      if (!mounted) return;
      setState(() {
        _shares = shares;
        _recent = recent.take(6).toList();
        _folderCounts = folderCounts;
        _fileCounts = fileCounts;
        _loading = false;
        _error = null;
      });
    } on DsmException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<List<FileEntry>> _safeFiles(DsmService service, String path) async {
    try {
      return await service.files(path);
    } catch (_) {
      return const [];
    }
  }

  void _openShare(ShareInfo share) {
    Navigator.of(context).push(appRoute(FilesBrowserPage(initialPath: share.path, initialTitle: share.name)));
  }

  Future<void> _uploadFlow() async {
    if (_shares.isEmpty) {
      showToast(context, '没有可用的共享文件夹', icon: Icons.info_outline_rounded);
      return;
    }
    final target = await showModalBottomSheet<ShareInfo>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(color: ctx.colors.textTertiary.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
              ),
              Text('上传到', style: ctx.texts.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              for (final share in _shares)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: ctx.colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(16),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      leading: const Icon(Icons.folder_rounded, color: Color(0xFF2E7BFF)),
                      title: Text(share.name, style: ctx.texts.titleSmall),
                      subtitle: Text(formatBytes(share.size), style: ctx.texts.labelSmall),
                      trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                      onTap: () => Navigator.pop(ctx, share),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (target == null || !mounted) return;
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    final service = context.read<AppState>().service!;
    var success = 0;
    for (final file in files) {
      try {
        await service.uploadStream(
          filename: file.name,
          stream: file.xFile.openRead(),
          length: await file.xFile.length(),
          destDir: target.path,
        );
        success++;
      } catch (e) {
        if (mounted) showToast(context, '「${file.name}」上传失败', icon: Icons.error_outline_rounded);
      }
    }
    if (success > 0 && mounted) {
      showToast(context, '已上传 $success 个文件到「${target.name}」');
      await _load(silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = context.watch<AppState>();
    final storage = state.storage;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PageScaffold(
        child: RefreshIndicator(
          onRefresh: _load,
          color: c.primary,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 132),
            children: [
              Entrance(
                index: 0,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('文件', style: context.texts.displayMedium),
                          const SizedBox(height: 4),
                          Text(
                            storage == null
                                ? '浏览你的私有云文件'
                                : '已用 ${formatBytes(storage.usedBytes)} · 共 ${formatBytes(storage.totalBytes)}',
                            style: context.texts.bodySmall?.copyWith(color: c.textTertiary, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(appRoute(const StoragePage())),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(13), boxShadow: c.cardShadow),
                        child: Row(
                          children: [
                            Icon(Icons.storage_rounded, size: 15, color: c.primary),
                            const SizedBox(width: 5),
                            Text(
                              storage == null ? '存储' : '${(storage.ratio * 100).toStringAsFixed(0)}%',
                              style: tabular(context.texts.labelLarge?.copyWith(color: c.primary, fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Entrance(
                index: 1,
                child: Row(
                  children: [
                    Expanded(
                      child: SearchPill(
                        hint: '搜索文件',
                        onTap: () => _openSearch(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
                )
              else if (_error != null)
                EmptyHint(
                  icon: Icons.cloud_off_rounded,
                  title: '无法读取文件列表',
                  subtitle: _error,
                  action: FilledButton(
                    onPressed: _load,
                    style: FilledButton.styleFrom(minimumSize: const Size(120, 42)),
                    child: const Text('重试'),
                  ),
                )
              else ...[
                Entrance(
                  index: 2,
                  child: Row(
                    children: [
                      Text('共享文件夹', style: context.texts.titleMedium),
                      const Spacer(),
                      Text('${_shares.length} 个', style: context.texts.labelSmall?.copyWith(color: c.textTertiary)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Entrance(
                  index: 3,
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.42,
                    ),
                    itemCount: _shares.length,
                    itemBuilder: (context, index) {
                      final share = _shares[index];
                      return _ShareCard(
                        share: share,
                        folders: _folderCounts[share.path],
                        files: _fileCounts[share.path],
                        onTap: () => _openShare(share),
                      );
                    },
                  ),
                ),
                if (_recent.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Entrance(
                    index: 4,
                    child: Row(
                      children: [
                        Text('最近修改', style: context.texts.titleMedium),
                        const Spacer(),
                        Text('自动同步', style: context.texts.labelSmall?.copyWith(color: c.textTertiary)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Entrance(
                    index: 5,
                    child: SoftCard(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          for (final file in _recent)
                            FileEntryTile(
                              entry: file,
                              showMore: false,
                              trailing: Icon(Icons.chevron_right_rounded, size: 17, color: c.textTertiary.withValues(alpha: 0.7)),
                              onTap: () {
                                final parent = file.path.substring(0, file.path.lastIndexOf('/'));
                                Navigator.of(context).push(appRoute(FilesBrowserPage(initialPath: parent, initialTitle: parent.split('/').last)));
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_shares.isEmpty)
                  const EmptyHint(icon: Icons.folder_off_rounded, title: '没有共享文件夹', subtitle: '请在 DSM 控制面板中创建共享文件夹'),
              ],
            ],
          ),
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 78),
        child: FloatingActionButton(
          onPressed: _uploadFlow,
          backgroundColor: c.primary,
          foregroundColor: Colors.white,
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19)),
          child: const Icon(Icons.add_rounded, size: 26),
        ),
      ),
    );
  }

  void _openSearch(BuildContext context) {
    final controller = TextEditingController();
    showAppSheet(
      context,
      title: '搜索文件',
      subtitle: '在最近修改的文件中查找',
      children: [
        StatefulBuilder(
          builder: (ctx, setStateSheet) {
            final query = controller.text.trim().toLowerCase();
            final matches = query.isEmpty
                ? <FileEntry>[]
                : _recent.where((e) => e.name.toLowerCase().contains(query)).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SearchPill(
                  controller: controller,
                  autofocus: true,
                  hint: '输入文件名',
                  onChanged: (_) => setStateSheet(() {}),
                ),
                const SizedBox(height: 14),
                if (query.isEmpty)
                  Text('输入关键词后显示结果', style: ctx.texts.bodySmall?.copyWith(color: ctx.colors.textTertiary))
                else if (matches.isEmpty)
                  Text('没有匹配的文件', style: ctx.texts.bodySmall?.copyWith(color: ctx.colors.textTertiary))
                else
                  for (final file in matches)
                    FileEntryTile(
                      entry: file,
                      showMore: false,
                      onTap: () {
                        Navigator.pop(context);
                        final parent = file.path.substring(0, file.path.lastIndexOf('/'));
                        Navigator.of(context).push(appRoute(FilesBrowserPage(initialPath: parent)));
                      },
                    ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ShareCard extends StatelessWidget {
  final ShareInfo share;
  final int? folders;
  final int? files;
  final VoidCallback onTap;
  const _ShareCard({required this.share, required this.onTap, this.folders, this.files});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final visual = _visualForShare(share.name);
    return SoftCard(
      padding: const EdgeInsets.all(14),
      radius: 22,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: visual),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: visual.last.withValues(alpha: 0.26), blurRadius: 12, offset: const Offset(0, 5))],
                ),
                child: Icon(_iconForShare(share.name), size: 21, color: Colors.white),
              ),
              const Spacer(),
              Icon(Icons.chevron_right_rounded, size: 17, color: c.textTertiary.withValues(alpha: 0.7)),
            ],
          ),
          const Spacer(),
          Text(share.name, style: context.texts.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Text(
            folders == null || files == null
                ? '正在统计…'
                : (folders == 0 && files == 0 ? '空文件夹' : '$folders 个文件夹 · $files 个文件'),
            style: tabular(context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  List<Color> _visualForShare(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('photo') || lower.contains('相册') || lower.contains('照片')) {
      return const [Color(0xFFB79BFF), Color(0xFF8A6BFF)];
    }
    if (lower.contains('video') || lower.contains('影视') || lower.contains('电影')) {
      return const [Color(0xFF6EC6FF), Color(0xFF3F8CFF)];
    }
    if (lower.contains('music') || lower.contains('音乐')) {
      return const [Color(0xFFFF9FB6), Color(0xFFFF6E93)];
    }
    if (lower.contains('back') || lower.contains('备份')) {
      return const [Color(0xFF5BD8A5), Color(0xFF1FB980)];
    }
    if (lower.contains('doc') || lower.contains('文档')) {
      return const [Color(0xFFFFB86B), Color(0xFFFF8F2E)];
    }
    return const [Color(0xFF6FB6FF), Color(0xFF2F7CFF)];
  }

  IconData _iconForShare(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('photo') || lower.contains('相册') || lower.contains('照片')) return Icons.photo_library_rounded;
    if (lower.contains('video') || lower.contains('影视') || lower.contains('电影')) return Icons.movie_rounded;
    if (lower.contains('music') || lower.contains('音乐')) return Icons.music_note_rounded;
    if (lower.contains('back') || lower.contains('备份')) return Icons.cloud_sync_rounded;
    if (lower.contains('doc') || lower.contains('文档')) return Icons.folder_copy_rounded;
    return Icons.folder_rounded;
  }
}
