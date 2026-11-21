import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';

import '../dsm/dsm_client.dart';
import '../dsm/models.dart';
import '../photos/immich_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icon_tile.dart';
import '../widgets/feedback.dart';
import '../widgets/surfaces.dart';
import '../widgets/ui_kit.dart';
import 'folder_picker_page.dart';

class PhotosPage extends StatefulWidget {
  const PhotosPage({super.key});

  @override
  State<PhotosPage> createState() => _PhotosPageState();
}

class _PhotosPageState extends State<PhotosPage> {
  final ScrollController _scroll = ScrollController();
  final List<PhotoItem> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _page = 1;
  static const int _pageSize = 80;
  ImmichClient? _immich;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _immich?.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 480) {
      _loadMore();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (!reset && (_loadingMore || !_hasMore)) return;
    final state = context.read<AppState>();
    final source = state.photoSource;
    if (!source.configured) {
      setState(() {
        _loading = false;
        _items.clear();
        _error = null;
        _hasMore = false;
      });
      return;
    }
    setState(() {
      if (reset) {
        _loading = true;
        _page = 1;
        _hasMore = true;
        _items.clear();
      } else {
        _loadingMore = true;
      }
      _error = null;
    });

    try {
      final fetched = await _fetch(state, source, reset ? 0 : _items.length, _page);
      if (!mounted) return;
      setState(() {
        _items.addAll(fetched.where((e) => _items.every((old) => old.id != e.id)));
        _items.sort((a, b) => (b.takenAt ?? DateTime(0)).compareTo(a.takenAt ?? DateTime(0)));
        _hasMore = fetched.length >= _pageSize;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
      if (fetched.isNotEmpty) _page++;
    } on DsmException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<List<PhotoItem>> _fetch(AppState state, PhotoSource source, int offset, int page) async {
    final service = state.service;
    switch (source.type) {
      case PhotoSourceType.none:
        return const [];
      case PhotoSourceType.folder:
        if (service == null) throw const DsmException(-1, '未连接群晖设备');
        if (source.folderPath.isEmpty) throw const DsmException(-1, '还没有选择相册目录');
        return service.folderPhotoPage(source.folderPath, offset: offset, limit: _pageSize);
      case PhotoSourceType.synologyPhotos:
        if (service == null) throw const DsmException(-1, '未连接群晖设备');
        return service.synologyPhotoItems(offset: offset, limit: _pageSize);
      case PhotoSourceType.immich:
        if (source.immichUrl.isEmpty) throw const DsmException(-1, '请先填写 Immich 地址');
        final client = _immich ??= ImmichClient(url: source.immichUrl, apiKey: source.immichKey, trustSelfSigned: source.trustSelfSigned);
        return client.search(page: page, size: _pageSize);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    await _load();
  }

  Future<void> _changeSource() async {
    final state = context.read<AppState>();
    await showAppSheet(
      context,
      title: '相册来源',
      subtitle: '选择照片从哪里读取',
      children: [
        _sourceOption(
          icon: Icons.folder_rounded,
          colors: const [Color(0xFF6FB6FF), Color(0xFF2F7CFF)],
          title: 'DSM 文件夹',
          subtitle: state.photoSource.type == PhotoSourceType.folder ? '当前：${state.photoSource.folderPath}' : '从共享文件夹读取图片',
          onTap: () async {
            Navigator.pop(context);
            final current = context.read<AppState>().photoSource;
            final startPath = current.type == PhotoSourceType.folder && current.folderPath.isNotEmpty ? current.folderPath : '/';
            final path = await Navigator.of(context).push<String>(appRoute(FolderPickerPage(initialPath: startPath)));
            if (path == null || !mounted) return;
            await state.setPhotoSource(PhotoSource(type: PhotoSourceType.folder, folderPath: path));
            _immich?.dispose();
            _immich = null;
            await _load(reset: true);
          },
        ),
        _sourceOption(
          icon: Icons.photo_library_rounded,
          colors: const [Color(0xFFB79BFF), Color(0xFF8A6BFF)],
          title: 'Synology Photos',
          subtitle: state.photoSource.type == PhotoSourceType.synologyPhotos ? '当前使用中' : '读取群晖 Photos 时间线',
          onTap: () async {
            Navigator.pop(context);
            await state.setPhotoSource(const PhotoSource(type: PhotoSourceType.synologyPhotos));
            _immich?.dispose();
            _immich = null;
            await _load(reset: true);
          },
        ),
        _sourceOption(
          icon: Icons.cloud_rounded,
          colors: const [Color(0xFF5BD8A5), Color(0xFF1FB980)],
          title: 'Immich',
          subtitle: state.photoSource.type == PhotoSourceType.immich ? '当前：${state.photoSource.immichUrl}' : '填写地址与 API Key',
          onTap: () async {
            Navigator.pop(context);
            final source = await showDialog<PhotoSource>(context: context, builder: (_) => _ImmichDialog(initial: state.photoSource));
            if (source == null || !mounted) return;
            await state.setPhotoSource(source);
            _immich?.dispose();
            _immich = null;
            await _load(reset: true);
          },
        ),
        if (state.photoSource.configured)
          SheetAction(
            icon: Icons.link_off_rounded,
            label: '清除相册来源',
            danger: true,
            onTap: () async {
              Navigator.pop(context);
              await state.setPhotoSource(const PhotoSource());
              await _load(reset: true);
            },
          ),
      ],
    );
  }

  Widget _sourceOption({
    required IconData icon,
    required List<Color> colors,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        padding: const EdgeInsets.all(14),
        radius: 18,
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: colors),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: colors.last.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 5))],
              ),
              child: Icon(icon, size: 22, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.texts.titleSmall),
                  const SizedBox(height: 2),
                  Text(subtitle, style: context.texts.labelSmall?.copyWith(color: context.colors.textTertiary), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: context.colors.textTertiary),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final source = state.photoSource;
    final c = context.colors;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PageScaffold(
        child: Column(
          children: [
            DetailHeader(
              title: '相册',
              subtitle: !source.configured
                  ? '选择照片来源'
                  : _items.isEmpty
                      ? source.label
                      : '${source.label} · ${_items.length} 张照片',
              actions: [
                CircleIconButton(icon: Icons.refresh_rounded, onTap: () => _load(reset: true), size: 20),
                const SizedBox(width: 6),
                CircleIconButton(icon: Icons.tune_rounded, onTap: _changeSource, size: 20),
              ],
            ),
            Expanded(child: !source.configured ? _buildSetup() : _buildGallery(c)),
          ],
        ),
      ),
    );
  }

  Widget _buildSetup() {
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
      children: [
        Center(
          child: Column(
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFB79BFF), Color(0xFF8A6BFF)]),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: const Color(0xFF8A6BFF).withValues(alpha: 0.3), blurRadius: 22, offset: const Offset(0, 10))],
                ),
                child: const Icon(Icons.photo_library_rounded, size: 36, color: Colors.white),
              ),
              const SizedBox(height: 16),
              Text('设置你的相册', style: context.texts.headlineSmall),
              const SizedBox(height: 6),
              Text(
                '可以读取 DSM 文件夹里的图片，也可以接入 Synology Photos 或 Immich。',
                textAlign: TextAlign.center,
                style: context.texts.bodySmall?.copyWith(color: c.textTertiary, height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _sourceOption(
          icon: Icons.folder_rounded,
          colors: const [Color(0xFF6FB6FF), Color(0xFF2F7CFF)],
          title: '选择 DSM 文件夹',
          subtitle: '从共享文件夹读取图片，没有 photo 文件夹也可以选别的',
          onTap: () async {
            final current = context.read<AppState>().photoSource;
            final startPath = current.type == PhotoSourceType.folder && current.folderPath.isNotEmpty ? current.folderPath : '/';
            final path = await Navigator.of(context).push<String>(appRoute(FolderPickerPage(initialPath: startPath)));
            if (path == null || !mounted) return;
            await context.read<AppState>().setPhotoSource(PhotoSource(type: PhotoSourceType.folder, folderPath: path));
            await _load(reset: true);
          },
        ),
        _sourceOption(
          icon: Icons.photo_library_rounded,
          colors: const [Color(0xFFB79BFF), Color(0xFF8A6BFF)],
          title: 'Synology Photos',
          subtitle: '群晖 Photos 的时间线、相册与缩略图',
          onTap: () async {
            await context.read<AppState>().setPhotoSource(const PhotoSource(type: PhotoSourceType.synologyPhotos));
            await _load(reset: true);
          },
        ),
        _sourceOption(
          icon: Icons.cloud_rounded,
          colors: const [Color(0xFF5BD8A5), Color(0xFF1FB980)],
          title: '接入 Immich',
          subtitle: '填写 Immich 地址与 API Key',
          onTap: () async {
            final source = await showDialog<PhotoSource>(context: context, builder: (_) => _ImmichDialog(initial: context.read<AppState>().photoSource));
            if (source == null || !mounted) return;
            await context.read<AppState>().setPhotoSource(source);
            await _load(reset: true);
          },
        ),
        const SizedBox(height: 8),
        Text(
          '提示：如果 DSM 中没有 photo 文件夹，可以在选择目录时点击右上角新建文件夹。',
          style: context.texts.labelSmall?.copyWith(color: c.textTertiary, height: 1.6),
        ),
      ],
    );
  }

  Widget _buildGallery(AppColors c) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (_error != null) {
      return Center(
        child: EmptyHint(
          icon: Icons.broken_image_rounded,
          title: '相册读取失败',
          subtitle: _error,
          action: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton(onPressed: () => _load(reset: true), child: const Text('重试')),
              const SizedBox(width: 10),
              OutlinedButton(onPressed: _changeSource, child: const Text('更换来源')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: EmptyHint(
          icon: Icons.photo_library_outlined,
          title: '这里还没有照片',
          subtitle: '换一个目录，或试试 Synology Photos / Immich',
          action: OutlinedButton(onPressed: _changeSource, child: const Text('更换来源')),
        ),
      );
    }

    final sections = <String, List<PhotoItem>>{};
    for (final item in _items) {
      final time = item.takenAt;
      final key = time == null ? '未知时间' : '${time.year}年${time.month}月';
      sections.putIfAbsent(key, () => []).add(item);
    }

    return CustomScrollView(
      controller: _scroll,
      physics: const BouncingScrollPhysics(),
      slivers: [
        for (final entry in sections.entries) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(
                children: [
                  Text(entry.key, style: context.texts.titleMedium?.copyWith(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text('${entry.value.length} 张', style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5)),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _PhotoTile(item: entry.value[index]),
                childCount: entry.value.length,
              ),
            ),
          ),
        ],
        if (_loadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.2)),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final PhotoItem item;
  const _PhotoTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(appRoute(_PhotoViewerPage(item: item))),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: c.surfaceAlt,
              child: item.thumbUrl.isEmpty
                  ? Center(child: Icon(Icons.image_rounded, size: 28, color: c.textTertiary))
                  : Image.network(
                      item.thumbUrl,
                      headers: item.headers,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, value: progress.expectedTotalBytes != null ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes! : null),
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => Center(child: Icon(Icons.broken_image_rounded, size: 24, color: c.textTertiary)),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoViewerPage extends StatefulWidget {
  final PhotoItem item;
  const _PhotoViewerPage({required this.item});

  @override
  State<_PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<_PhotoViewerPage> {
  Map<String, dynamic>? _fileInfo;

  PhotoItem get item => widget.item;

  @override
  void initState() {
    super.initState();
    if (item.path.isNotEmpty) _loadInfo();
  }

  Future<void> _loadInfo() async {
    final service = context.read<AppState>().service;
    if (service == null) return;
    try {
      final info = await service.fileInfo(item.path);
      if (mounted) setState(() => _fileInfo = info);
    } catch (_) {}
  }

  Future<void> _showDetails() async {
    final c = context.colors;
    final info = _fileInfo;
    final additional = (info?['additional'] as Map?)?.cast<String, dynamic>() ?? const {};
    final time = (additional['time'] as Map?)?.cast<String, dynamic>() ?? const {};
    final mtime = (time['mtime'] as num?)?.toInt();
    final size = (additional['size'] as num?)?.toInt() ?? item.size;
    final date = mtime != null ? DateTime.fromMillisecondsSinceEpoch(mtime * 1000) : (item.takenAt ?? item.createdAt);
    String fmt(DateTime? value) => value == null ? '未知' : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    await showAppSheet(
      context,
      title: '图片详情',
      subtitle: item.name,
      children: [
        SoftCard(
          shadow: false,
          color: c.surfaceAlt,
          child: Column(
            children: [
              _detailRow('文件名', item.name),
              _detailRow('大小', size > 0 ? formatBytes(size) : '未知'),
              _detailRow('时间', fmt(date)),
              _detailRow('路径', item.path.isEmpty ? '相册索引（无本地路径）' : item.path),
            ],
          ),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 52, child: Text(label, style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 11))),
          Expanded(child: SelectableText(value, style: context.texts.bodySmall?.copyWith(color: c.textPrimary, fontSize: 12, height: 1.4))),
        ],
      ),
    );
  }

  Future<void> _share() async {
    final service = context.read<AppState>().service;
    if (service == null || item.path.isEmpty) {
      showToast(context, '这张图片没有可分享的 DSM 路径', icon: Icons.info_outline_rounded);
      return;
    }
    try {
      final link = await service.createSharingLink(item.path);
      if (!mounted) return;
      await showAppSheet(
        context,
        title: '共享链接已创建',
        subtitle: item.name,
        children: [
          SoftCard(
            shadow: false,
            color: context.colors.surfaceAlt,
            child: SelectableText(link.url, style: context.texts.bodySmall?.copyWith(color: context.colors.textPrimary, height: 1.5)),
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
    final url = item.originalUrl.isNotEmpty ? item.originalUrl : item.thumbUrl;
    return Scaffold(
      backgroundColor: const Color(0xFF08090D),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (item.takenAt != null)
                          Text(
                            '${item.takenAt!.year}-${item.takenAt!.month.toString().padLeft(2, '0')}-${item.takenAt!.day.toString().padLeft(2, '0')}',
                            style: const TextStyle(color: Colors.white38, fontSize: 11.5),
                          ),
                      ],
                    ),
                  ),
                  _viewerAction(Icons.info_outline_rounded, _showDetails),
                  if (item.path.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _viewerAction(Icons.share_rounded, _share),
                  ],
                ],
              ),
            ),
            Expanded(
              child: url.isEmpty
                  ? const Center(child: Icon(Icons.image_not_supported_rounded, size: 48, color: Colors.white24))
                  : InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 4,
                      child: Center(
                        child: Image.network(
                          url,
                          headers: item.headers,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const Center(child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white54));
                          },
                          errorBuilder: (_, __, ___) => item.thumbUrl.isNotEmpty && item.thumbUrl != url
                              ? Image.network(item.thumbUrl, headers: item.headers, fit: BoxFit.contain)
                              : const Icon(Icons.broken_image_rounded, size: 48, color: Colors.white24),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _viewerAction(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }
}
class _ImmichDialog extends StatefulWidget {
  final PhotoSource initial;
  const _ImmichDialog({required this.initial});

  @override
  State<_ImmichDialog> createState() => _ImmichDialogState();
}

class _ImmichDialogState extends State<_ImmichDialog> {
  late final TextEditingController _url = TextEditingController(text: widget.initial.immichUrl);
  late final TextEditingController _key = TextEditingController(text: widget.initial.immichKey);
  bool _testing = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final url = _url.text.trim();
    final key = _key.text.trim();
    if (url.isEmpty) {
      setState(() => _error = '请填写 Immich 地址');
      return;
    }
    setState(() {
      _testing = true;
      _error = null;
    });
    final client = ImmichClient(url: url, apiKey: key);
    try {
      await client.testConnection();
      if (!mounted) return;
      setState(() => _error = null);
      showToast(context, 'Immich 连接成功');
    } on DsmException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      client.dispose();
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AlertDialog(
      title: const Text('连接 Immich'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _url,
            decoration: const InputDecoration(hintText: 'http://192.168.1.10:2283'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _key,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'Immich API Key'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(_error!, style: context.texts.labelSmall?.copyWith(color: c.danger)),
            ),
          ],
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'API Key 需要资产读取权限（asset.read / asset.view）。',
              style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: _testing ? null : _test, child: Text(_testing ? '测试中…' : '测试连接')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        TextButton(
          onPressed: () {
            final source = PhotoSource(
              type: PhotoSourceType.immich,
              immichUrl: _url.text.trim(),
              immichKey: _key.text.trim(),
              trustSelfSigned: true,
            );
            Navigator.pop(context, source);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
