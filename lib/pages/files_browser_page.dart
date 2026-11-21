import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dsm/dsm_client.dart';
import '../dsm/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icon_tile.dart';
import '../widgets/feedback.dart';
import '../widgets/file_visual.dart';
import '../widgets/nav_bar.dart';
import '../widgets/surfaces.dart';
import '../widgets/ui_kit.dart';

class FilesBrowserPage extends StatefulWidget {
  final String initialPath;
  final String? initialTitle;
  const FilesBrowserPage({super.key, required this.initialPath, this.initialTitle});

  @override
  State<FilesBrowserPage> createState() => _FilesBrowserPageState();
}

class _FilesBrowserPageState extends State<FilesBrowserPage> {
  late String _path = widget.initialPath;
  late String _title = widget.initialTitle ?? _nameOf(widget.initialPath);
  List<FileEntry> _entries = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  final _searchController = TextEditingController();

  static String _nameOf(String path) {
    if (path.isEmpty || path == '/') return '全部文件';
    final parts = path.split('/').where((e) => e.isNotEmpty).toList();
    return parts.isEmpty ? '全部文件' : parts.last;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final service = context.read<AppState>().service;
    if (service == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await service.files(_path);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
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

  List<FileEntry> get _visible {
    if (_query.isEmpty) return _entries;
    final q = _query.toLowerCase();
    return _entries.where((e) => e.name.toLowerCase().contains(q)).toList();
  }

  Future<void> _enterFolder(FileEntry entry) async {
    setState(() {
      _path = entry.path;
      _title = entry.name;
      _query = '';
      _searchController.clear();
    });
    await _load();
  }

  Future<void> _goUp() async {
    if (_path == widget.initialPath) {
      Navigator.of(context).maybePop();
      return;
    }
    final index = _path.lastIndexOf('/');
    final parent = index <= 0 ? '/' : _path.substring(0, index);
    setState(() {
      _path = parent == '/' ? widget.initialPath : parent;
      _title = _nameOf(_path);
    });
    await _load();
  }

  Future<void> _newFolder() async {
    final name = await showInputDialog(context, title: '新建文件夹', hint: '文件夹名称');
    if (name == null) return;
    await _perform(() async {
      await context.read<AppState>().service!.createFolder(_path, name);
      showToast(context, '已创建「$name」');
      await _load();
    });
  }

  Future<void> _upload() async {
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
          destDir: _path,
        );
        success++;
      } catch (e) {
        if (mounted) showToast(context, '「${file.name}」上传失败：$e', icon: Icons.error_outline_rounded);
      }
    }
    if (success > 0 && mounted) {
      showToast(context, '已上传 $success 个文件');
      await _load();
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
    } on DsmException catch (e) {
      if (mounted) showToast(context, e.message, icon: Icons.error_outline_rounded);
    } catch (e) {
      if (mounted) showToast(context, '$e', icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _open(FileEntry entry) async {
    if (entry.isDir) return _enterFolder(entry);
    if (entry.kind == FileKind.image) {
      Navigator.of(context).push(appRoute(_ImagePreviewPage(name: entry.name, path: entry.path)));
      return;
    }
    _showFileActions(entry);
  }

  void _showFileActions(FileEntry entry) {
    showAppSheet(
      context,
      title: entry.name,
      subtitle: entry.isDir ? '文件夹' : formatBytes(entry.size),
      children: [
        SheetAction(
          icon: Icons.share_rounded,
          label: '创建共享链接',
          subtitle: '生成群晖共享链接，可发给朋友',
          onTap: () {
            Navigator.pop(context);
            _shareLink(entry);
          },
        ),
        if (!entry.isDir)
          SheetAction(
            icon: Icons.download_rounded,
            label: '下载到本机',
            onTap: () async {
              Navigator.pop(context);
              await _download(entry);
            },
          ),
        SheetAction(
          icon: Icons.drive_file_rename_outline_rounded,
          label: '重命名',
          onTap: () async {
            Navigator.pop(context);
            final name = await showInputDialog(context, title: '重命名', initial: entry.name, hint: '新名称');
            if (name == null) return;
            await _perform(() async {
              await context.read<AppState>().service!.rename(entry.path, name);
              showToast(context, '已重命名');
              await _load();
            });
          },
        ),
        SheetAction(
          icon: Icons.info_outline_rounded,
          label: '详细信息',
          onTap: () {
            Navigator.pop(context);
            showAppSheet(
              context,
              title: entry.name,
              children: [
                SoftCard(
                  shadow: false,
                  color: context.colors.surfaceAlt,
                  child: Column(
                    children: [
                      InfoRow(label: '路径', value: entry.path),
                      InfoRow(label: '类型', value: visualFor(entry.kind, extension: entry.extension).label),
                      InfoRow(label: '大小', value: entry.isDir ? '—' : formatBytes(entry.size)),
                      InfoRow(label: '修改时间', value: entry.mtime == null ? '—' : '${entry.mtime!.year}-${entry.mtime!.month}-${entry.mtime!.day} ${entry.mtime!.hour.toString().padLeft(2, '0')}:${entry.mtime!.minute.toString().padLeft(2, '0')}'),
                      InfoRow(label: '所有者', value: entry.owner.isEmpty ? '—' : entry.owner),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        SheetAction(
          icon: Icons.delete_outline_rounded,
          label: '删除',
          danger: true,
          onTap: () async {
            Navigator.pop(context);
            final ok = await showConfirm(context, title: '删除「${entry.name}」？', message: '删除后可在 DSM 的回收站中找回（如已启用）。', confirmText: '删除', danger: true);
            if (!ok) return;
            await _perform(() async {
              await context.read<AppState>().service!.delete([entry.path]);
              showToast(context, '已删除');
              await _load();
            });
          },
        ),
      ],
    );
  }

  Future<void> _download(FileEntry entry) async {
    final state = context.read<AppState>();
    if (state.demo) {
      showToast(context, '演示模式不会真正下载文件', icon: Icons.info_outline_rounded);
      return;
    }
    final uri = state.service!.downloadUri(entry.path);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) showToast(context, '无法打开下载链接', icon: Icons.error_outline_rounded);
  }

  Future<void> _shareLink(FileEntry entry) async {
    final service = context.read<AppState>().service;
    if (service == null) return;
    final options = await showModalBottomSheet<_ShareOptions>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShareSheet(fileName: entry.name),
    );
    if (options == null) return;
    final expireDate = options.days <= 0 ? null : DateTime.now().add(Duration(days: options.days));
    try {
      final link = await service.createSharingLink(
        entry.path,
        password: options.password,
        expireDate: expireDate,
        expireTimes: options.times,
      );
      if (!mounted) return;
      await showAppSheet(
        context,
        title: '共享链接已创建',
        subtitle: entry.name,
        children: [
          SoftCard(
            shadow: false,
            color: context.colors.surfaceAlt,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(link.url, style: context.texts.bodySmall?.copyWith(color: context.colors.textPrimary, height: 1.5)),
                const SizedBox(height: 8),
                Text(
                  [
                    if (expireDate != null) '有效期至 ${expireDate.year}-${expireDate.month.toString().padLeft(2, '0')}-${expireDate.day.toString().padLeft(2, '0')}' else '有效期：永久',
                    if (options.password != null) '密码保护已开启',
                    if (options.times != null) '限制访问 ${options.times} 次',
                  ].join(' · '),
                  style: context.texts.labelSmall?.copyWith(color: context.colors.textTertiary, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: link.url));
                    if (mounted) showToast(context, '链接已复制');
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('复制链接'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => launchUrl(Uri.parse(link.url), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('打开链接'),
                ),
              ),
            ],
          ),
        ],
      );
    } on DsmException catch (e) {
      if (mounted) showToast(context, e.message, icon: Icons.error_outline_rounded);
    }
  }
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final entries = _visible;
    final folders = entries.where((e) => e.isDir).length;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PageScaffold(
        child: Column(
          children: [
            DetailHeader(
              title: _title,
              subtitle: _path.isEmpty ? '共享文件夹' : '$_path · $folders 个文件夹，${entries.length - folders} 个文件',
              onBack: _goUp,
              actions: [
                CircleIconButton(icon: Icons.refresh_rounded, onTap: _load, size: 20),
                const SizedBox(width: 2),
                CircleIconButton(
                  icon: Icons.create_new_folder_outlined,
                  onTap: _newFolder,
                  size: 20,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: SearchPill(
                controller: _searchController,
                hint: '搜索当前文件夹',
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
            Expanded(child: _buildBody(entries)),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: FloatingActionButton.extended(
          onPressed: _upload,
          backgroundColor: c.primary,
          foregroundColor: Colors.white,
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          icon: const Icon(Icons.upload_rounded, size: 20),
          label: Text('上传', style: context.texts.titleSmall?.copyWith(color: Colors.white)),
        ),
      ),
    );
  }

  Widget _buildBody(List<FileEntry> entries) {
    final c = context.colors;
    if (_loading) {
      return Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4, color: c.primary)));
    }
    if (_error != null) {
      return Center(
        child: EmptyHint(
          icon: Icons.cloud_off_rounded,
          title: '无法读取此文件夹',
          subtitle: _error,
          action: FilledButton(
            onPressed: _load,
            style: FilledButton.styleFrom(minimumSize: const Size(120, 42)),
            child: const Text('重试'),
          ),
        ),
      );
    }
    if (entries.isEmpty) {
      return const Center(child: EmptyHint(icon: Icons.folder_open_rounded, title: '这里还是空的', subtitle: '上传文件或新建文件夹开始使用'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: c.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
        children: [
          _PathChips(path: _path, onTap: (target) async {
            setState(() {
              _path = target.isEmpty ? widget.initialPath : target;
              _title = _nameOf(_path);
            });
            await _load();
          }),
          const SizedBox(height: 6),
          SoftCard(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              children: [
                for (var i = 0; i < entries.length && i < 400; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 68, color: c.border.withValues(alpha: 0.55)),
                  FileEntryTile(
                    entry: entries[i],
                    onTap: () => _open(entries[i]),
                    onMore: () => _showFileActions(entries[i]),
                    showMore: false,
                    trailing: Icon(Icons.chevron_right_rounded, size: 17, color: c.textTertiary.withValues(alpha: 0.7)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PathChips extends StatelessWidget {
  final String path;
  final ValueChanged<String> onTap;
  const _PathChips({required this.path, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final parts = path.split('/').where((e) => e.isNotEmpty).toList();
    final chips = <Widget>[];
    for (var i = 0; i < parts.length; i++) {
      final target = '/${parts.take(i + 1).join('/')}';
      final isLast = i == parts.length - 1;
      chips.add(
        GestureDetector(
          onTap: () => onTap(target),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text(
              parts[i],
              style: context.texts.labelMedium?.copyWith(
                color: isLast ? c.textPrimary : c.textTertiary,
                fontWeight: isLast ? FontWeight.w600 : FontWeight.w500,
                fontSize: 11.5,
              ),
            ),
          ),
        ),
      );
      if (!isLast) {
        chips.add(Icon(Icons.chevron_right_rounded, size: 14, color: c.textTertiary.withValues(alpha: 0.6)));
      }
    }
    return SizedBox(
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        children: chips,
      ),
    );
  }
}

class _ImagePreviewPage extends StatelessWidget {
  final String name;
  final String path;
  const _ImagePreviewPage({required this.name, required this.path});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final uri = state.demo ? null : state.service?.downloadUri(path, open: true);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0C12),
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: name,
              showBack: true,
              actions: const [],
            ),
            Expanded(
              child: uri == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.image_rounded, size: 56, color: Colors.white24),
                          const SizedBox(height: 12),
                          Text('演示模式不加载真实图片', style: context.texts.bodySmall?.copyWith(color: Colors.white38)),
                        ],
                      ),
                    )
                  : InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 4,
                      child: Center(
                        child: Image.network(
                          uri.toString(),
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const Center(child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white54));
                          },
                          errorBuilder: (context, error, stack) => Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.broken_image_rounded, size: 52, color: Colors.white24),
                              const SizedBox(height: 10),
                              Text('图片加载失败', style: context.texts.bodySmall?.copyWith(color: Colors.white38)),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareOptions {
  final int days;
  final String? password;
  final int? times;
  const _ShareOptions({required this.days, this.password, this.times});
}

class _ShareSheet extends StatefulWidget {
  final String fileName;
  const _ShareSheet({required this.fileName});

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  int _days = 0;
  bool _passwordEnabled = false;
  bool _timesEnabled = false;
  final _password = TextEditingController();
  final _times = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _times.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(color: c.textTertiary.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 14),
                Text('创建共享链接', textAlign: TextAlign.center, style: context.texts.titleLarge),
                const SizedBox(height: 4),
                Text(widget.fileName, textAlign: TextAlign.center, style: context.texts.bodySmall?.copyWith(color: c.textTertiary)),
                const SizedBox(height: 18),
                Text('有效期', style: context.texts.labelLarge?.copyWith(fontSize: 12.5, color: c.textSecondary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final item in const [(0, '永久'), (1, '1 天'), (7, '7 天'), (30, '30 天')])
                      _DayChip(
                        label: item.$2,
                        selected: _days == item.$1,
                        onTap: () => setState(() => _days = item.$1),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('密码保护', style: context.texts.titleSmall?.copyWith(fontSize: 13.5)),
                  subtitle: Text('访问者需要输入密码', style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5)),
                  value: _passwordEnabled,
                  onChanged: (value) => setState(() => _passwordEnabled = value),
                ),
                if (_passwordEnabled)
                  TextField(
                    controller: _password,
                    obscureText: false,
                    decoration: const InputDecoration(hintText: '设置访问密码'),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('限制访问次数', style: context.texts.titleSmall?.copyWith(fontSize: 13.5)),
                  subtitle: Text('访问达到次数后链接失效', style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5)),
                  value: _timesEnabled,
                  onChanged: (value) => setState(() => _timesEnabled = value),
                ),
                if (_timesEnabled)
                  TextField(
                    controller: _times,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '允许访问次数，例如 10'),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    final password = _passwordEnabled ? _password.text.trim() : null;
                    final times = _timesEnabled ? int.tryParse(_times.text.trim()) : null;
                    Navigator.pop(
                      context,
                      _ShareOptions(
                        days: _days,
                        password: password == null || password.isEmpty ? null : password,
                        times: times != null && times > 0 ? times : null,
                      ),
                    );
                  },
                  child: const Text('创建链接'),
                ),
                const SizedBox(height: 8),
                Text(
                  '有效期与访问次数由群晖共享链接服务执行；密码会一并写入链接配置。',
                  textAlign: TextAlign.center,
                  style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DayChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.primary : c.surfaceAlt,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(label, style: context.texts.labelMedium?.copyWith(fontSize: 12, color: selected ? Colors.white : c.textSecondary)),
      ),
    );
  }
}