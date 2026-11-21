import 'dart:io';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';

import '../dsm/dsm_client.dart';
import '../dsm/models.dart';
import '../photos/immich_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icon_tile.dart';
import '../widgets/feedback.dart';
import '../widgets/share_sheet.dart';
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
  StreamSubscription<PhotoItem>? _folderSub;
  int _folderGen = 0;
  final Set<String> _seen = {};
  bool _refreshing = false;
  bool _sortDesc = true;
  static final Map<String, _PhotoCache> _cache = {};

  @override
  void initState() {
    super.initState();
    final source = context.read<AppState>().photoSource;
    final cached = _cache[_cacheKey(source)];
    if (cached != null) {
      _items.addAll(cached.items);
      _hasMore = cached.hasMore;
      _loading = false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true, background: cached != null));
    _scroll.addListener(_onScroll);
  }

  String _cacheKey(PhotoSource source) => switch (source.type) {
        PhotoSourceType.folder => 'folder:',
        PhotoSourceType.synologyPhotos => 'photos',
        PhotoSourceType.immich => 'immich:',
        PhotoSourceType.none => '',
      };

  @override
  void dispose() {
    _folderSub?.cancel();
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

  Future<void> _load({bool reset = false, bool background = false}) async {
    if (!reset && (_loadingMore || !_hasMore)) return;
    final previous = List<PhotoItem>.from(_items);
    final state = context.read<AppState>();
    final source = state.photoSource;
    if (source.type == PhotoSourceType.folder) {
      if (background) {
        final cached = _cache[_cacheKey(source)];
        final stale = cached == null || cached.items.length < 20 || DateTime.now().difference(cached.savedAt) > const Duration(minutes: 5);
        if (stale) await _startFolderStream(state, source, keepExisting: true);
        return;
      }
      await _startFolderStream(state, source);
      return;
    }
    if (!source.configured) {
      setState(() {
        _loading = false;
        _items.clear();
        _error = null;
        _hasMore = false;
      });
      return;
    }
    if (!background) {
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
    }

    try {
      final fetched = await _fetch(state, source, reset ? 0 : _items.length, _page);
      if (!mounted) return;
      setState(() {
        if (background) _items.clear();
        _items.addAll(fetched.where((e) => _items.every((old) => old.id != e.id)));
        _items.sort((a, b) => _sortDesc ? (b.takenAt ?? DateTime(0)).compareTo(a.takenAt ?? DateTime(0)) : (a.takenAt ?? DateTime(0)).compareTo(b.takenAt ?? DateTime(0)));
        _hasMore = fetched.length >= _pageSize;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
      if (fetched.isNotEmpty) _page++;
      _cache[_cacheKey(source)] = _PhotoCache(List.unmodifiable(_items.take(500).toList()), _hasMore, DateTime.now());
    } on DsmException catch (e) {
      if (!mounted) return;
      if (background) {
        if (mounted) setState(() => _items..clear()..addAll(previous));
        return;
      }
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

  Future<void> _startFolderStream(AppState state, PhotoSource source, {bool keepExisting = false}) async {
    final generation = ++_folderGen;
    final service = state.service;
    if (service == null) {
      setState(() {
        _error = '未连接群晖设备';
        _loading = false;
      });
      return;
    }
    if (source.folderPath.isEmpty) {
      setState(() {
        _error = '还没有选择相册目录';
        _loading = false;
      });
      return;
    }
    await _folderSub?.cancel();
    if (!keepExisting) _seen.clear();
    setState(() {
      _loading = !keepExisting;
      _refreshing = keepExisting;
      if (!keepExisting) _items.clear();
      _hasMore = false;
      _loadingMore = false;
      _error = null;
    });
    if (keepExisting) _seen.addAll(_items.map((e) => e.id));
    _folderSub = service.folderPhotoStream(source.folderPath).listen(
      (item) {
        if (!mounted || generation != _folderGen) return;
        if (!_seen.add(item.id)) return;
        setState(() {
          _loading = false;
          _refreshing = false;
          _items.add(item);
          _items.sort((a, b) => _sortDesc ? (b.takenAt ?? DateTime(0)).compareTo(a.takenAt ?? DateTime(0)) : (a.takenAt ?? DateTime(0)).compareTo(b.takenAt ?? DateTime(0)));
        });
      },
      onError: (Object e) {
        if (!mounted || generation != _folderGen) return;
        setState(() {
          _error = '';
          _loading = false;
        });
      },
      onDone: () {
        if (!mounted || generation != _folderGen) return;
        setState(() {
          _loading = false;
          _refreshing = false;
          _hasMore = false;
        });
        _cache[_cacheKey(source)] = _PhotoCache(List.unmodifiable(_items.take(500).toList()), false, DateTime.now());
      },
    );
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

  void _toggleSort() {
    setState(() {
      _sortDesc = !_sortDesc;
      _items.sort((a, b) => _sortDesc ? (b.takenAt ?? DateTime(0)).compareTo(a.takenAt ?? DateTime(0)) : (a.takenAt ?? DateTime(0)).compareTo(b.takenAt ?? DateTime(0)));
    });
    showToast(context, _sortDesc ? '日期：新 → 旧' : '日期：旧 → 新');
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    final state = context.read<AppState>();
    final source = state.photoSource;
    setState(() => _refreshing = true);
    if (source.type == PhotoSourceType.folder) {
      await _startFolderStream(state, source, keepExisting: true);
      return;
    }
    try {
      final fetched = await _fetch(state, source, 0, 1);
      if (!mounted) return;
      setState(() {
        for (final item in fetched) {
          if (_seen.add(item.id)) _items.add(item);
        }
        _items.sort((a, b) => (b.takenAt ?? DateTime(0)).compareTo(a.takenAt ?? DateTime(0)));
      });
      _cache[_cacheKey(source)] = _PhotoCache(List.unmodifiable(_items.take(500).toList()), _hasMore, DateTime.now());
    } catch (_) {} finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _loadMore() async {
    if (_refreshing) return;
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
                _refreshing
                      ? const SizedBox(width: 38, height: 38, child: Padding(padding: EdgeInsets.all(9), child: CircularProgressIndicator(strokeWidth: 2.2)))
                      : CircleIconButton(icon: Icons.refresh_rounded, onTap: _refresh, size: 20),
                const SizedBox(width: 6),
                CircleIconButton(icon: Icons.swap_vert_rounded, onTap: _toggleSort, size: 18),
                  const SizedBox(width: 4),
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
    Widget placeholder() => Center(child: Icon(Icons.image_rounded, size: 28, color: c.textTertiary));
    Widget broken() => Center(child: Icon(Icons.broken_image_rounded, size: 24, color: c.textTertiary));
    Widget original() => Image.network(
          item.originalUrl,
          headers: item.headers,
          fit: BoxFit.cover,
          cacheWidth: 480,
          errorBuilder: (_, __, ___) => broken(),
        );
    Widget image;
    if (item.thumbUrl.isEmpty) {
      image = item.originalUrl.isEmpty ? placeholder() : original();
    } else {
      image = Image.network(
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
        errorBuilder: (_, __, ___) => item.originalUrl.isEmpty ? broken() : original(),
      );
    }
    return GestureDetector(
      onTap: () => Navigator.of(context).push(appRoute(_PhotoViewerPage(item: item))),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [ColoredBox(color: c.surfaceAlt, child: image)],
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
  bool _chrome = true;
  String? _busyAction;

  PhotoItem get item => widget.item;

  String get _url => item.originalUrl.isNotEmpty ? item.originalUrl : item.thumbUrl;

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

  String _fmt(DateTime? value) => value == null ? '未知' : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  Future<void> _showDetails() async {
    final c = context.colors;
    final info = _fileInfo;
    final additional = (info?['additional'] as Map?)?.cast<String, dynamic>() ?? const {};
    final time = (additional['time'] as Map?)?.cast<String, dynamic>() ?? const {};
    final mtime = (time['mtime'] as num?)?.toInt();
    final size = (additional['size'] as num?)?.toInt() ?? item.size;
    final date = mtime != null ? DateTime.fromMillisecondsSinceEpoch(mtime * 1000) : (item.takenAt ?? item.createdAt);
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
              _detailRow('时间', _fmt(date)),
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

  Future<void> _showLink(String url) async {
    await showAppSheet(
      context,
      title: '分享链接已创建',
      subtitle: item.name,
      children: [
        SoftCard(
          shadow: false,
          color: context.colors.surfaceAlt,
          child: SelectableText(url, style: context.texts.bodySmall?.copyWith(color: context.colors.textPrimary, height: 1.5)),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: url));
                  if (mounted) showToast(context, '链接已复制');
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('复制链接'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('打开链接'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _share() async {
    if (_busyAction != null) return;
    final state = context.read<AppState>();
    final source = state.photoSource;
    if (source.type == PhotoSourceType.folder && item.path.isNotEmpty) {
      final service = state.service;
      if (service == null) return;
      final options = await showShareOptions(context, fileName: item.name);
      if (options == null) return;
      final expireDate = options.days <= 0 ? null : DateTime.now().add(Duration(days: options.days));
      try {
        final link = await service.createSharingLink(
          item.path,
          password: options.password,
          expireDate: expireDate,
          expireTimes: options.times,
        );
        if (mounted) _showLink(link.url);
      } on DsmException catch (e) {
        if (mounted) showToast(context, e.message, icon: Icons.error_outline_rounded);
      }
      return;
    }
    if (source.type == PhotoSourceType.immich) {
      final client = ImmichClient(url: source.immichUrl, apiKey: source.immichKey, trustSelfSigned: source.trustSelfSigned);
      try {
        final url = await client.createShareLink(item.id);
        if (mounted) _showLink(url);
        client.dispose();
        return;
      } catch (_) {
        client.dispose();
      }
    }
    await _shareFile();
  }

  Future<void> _shareFile() async {
    if (_url.isEmpty) {
      showToast(context, '没有可分享的图片地址', icon: Icons.info_outline_rounded);
      return;
    }
    setState(() => _busyAction = 'share');
    try {
      final response = await http.get(Uri.parse(_url), headers: item.headers).timeout(const Duration(seconds: 40));
      if (response.statusCode != 200) {
        throw DsmException(-1, '下载图片失败（HTTP ${response.statusCode}）');
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${item.name.isEmpty ? 'photo.jpg' : item.name}');
      await file.writeAsBytes(response.bodyBytes);
      if (!mounted) return;
      await Share.shareXFiles([XFile(file.path)], text: item.name);
    } catch (e) {
      if (mounted) showToast(context, '分享失败：$e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _saveImage() async {
    if (_url.isEmpty) return;
    setState(() => _busyAction = 'save');
    try {
      final response = await http.get(Uri.parse(_url), headers: item.headers).timeout(const Duration(seconds: 40));
      if (response.statusCode != 200) throw DsmException(-1, '下载图片失败（HTTP ${response.statusCode}）');
      final bytes = response.bodyBytes;
      final uri = await FilePicker.saveFile(
        dialogTitle: '保存图片',
        fileName: item.name.isEmpty ? 'photo.jpg' : item.name,
        bytes: bytes,
      );
      if (uri == null) return;
      if (mounted) showToast(context, '图片已保存');
    } catch (e) {
      if (mounted) showToast(context, '保存失败：', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = item.takenAt ?? item.createdAt;
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.surfaceAlt,
      body: Column(
        children: [
          if (_chrome)
            Container(
              color: c.surface,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                  child: Row(
                    children: [
                      _circleAction(Icons.arrow_back_ios_new_rounded, () => Navigator.of(context).maybePop()),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              date == null ? '图片' : '${date.month}月${date.day}日',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: c.textPrimary, fontSize: 17, fontWeight: FontWeight.w600),
                            ),
                            if (date != null)
                              Text(
                                '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: c.textTertiary, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _circleAction(Icons.more_vert_rounded, _showDetails),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _chrome = !_chrome),
              child: _url.isEmpty
                  ? Center(child: Icon(Icons.image_not_supported_rounded, size: 48, color: c.textTertiary))
                  : InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 4,
                      child: Center(
                        child: Image.network(
                          _url,
                          headers: item.headers,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Center(child: CircularProgressIndicator(strokeWidth: 2.2, color: c.textTertiary));
                          },
                          errorBuilder: (_, __, ___) => item.thumbUrl.isNotEmpty && item.thumbUrl != _url
                              ? Image.network(item.thumbUrl, headers: item.headers, fit: BoxFit.contain)
                              : Icon(Icons.broken_image_rounded, size: 48, color: c.textTertiary),
                        ),
                      ),
                    ),
            ),
          ),
          if (_chrome)
            Container(
              color: c.surface,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _bottomAction(Icons.share_rounded, '分享', _share, busy: _busyAction == 'share'),
                      const SizedBox(width: 84),
                      _bottomAction(Icons.download_rounded, '保存图片', _saveImage, busy: _busyAction == 'save'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
  Widget _circleAction(IconData icon, VoidCallback onTap) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(13)),
        child: Icon(icon, size: 18, color: c.textPrimary),
      ),
    );
  }

  Widget _bottomAction(IconData icon, String label, VoidCallback onTap, {bool busy = false}) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          busy
              ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary))
              : Icon(icon, color: c.textPrimary, size: 23),
          const SizedBox(height: 5),
          Text(label, style: TextStyle(color: c.textPrimary, fontSize: 11)),
        ],
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

class _PhotoCache {
  final List<PhotoItem> items;
  final bool hasMore;
  final DateTime savedAt;
  const _PhotoCache(this.items, this.hasMore, this.savedAt);
}