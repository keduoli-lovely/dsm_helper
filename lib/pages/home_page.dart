import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../downloads/download_tools.dart';
import '../dsm/dsm_client.dart';
import '../dsm/dsm_service.dart';
import '../dsm/models.dart';
import '../photos/immich_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icon_tile.dart';
import '../widgets/feedback.dart';
import '../widgets/file_visual.dart';
import '../widgets/nas_device.dart';
import '../widgets/nav_bar.dart';
import '../widgets/surfaces.dart';
import '../widgets/ui_kit.dart';
import '../widgets/user_avatar.dart';
import 'docker_page.dart';
import 'files_browser_page.dart';
import 'logs_page.dart';
import 'monitor_page.dart';
import 'photos_page.dart';
import 'shared_links_page.dart';
import 'storage_page.dart';
import 'users_page.dart';

class HomePage extends StatefulWidget {
  final void Function(int tab) onOpenTab;
  const HomePage({super.key, required this.onOpenTab});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  Timer? _timer;
  List<DownloadTask> _downloads = [];
  List<DsmPackage> _packages = [];
  List<LogEntry> _logs = [];
  List<FileEntry> _recentFiles = [];
  List<PhotoItem> _photos = [];
  List<DockerContainer> _dockerContainers = [];
  Map<String, dynamic>? _network;
  bool _busy = false;
  bool _editing = false;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      _tick++;
      _refreshUtilization();
      if (_tick % 3 == 0) context.read<AppState>().measureLatency();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _refreshUtilization() async {
    final state = context.read<AppState>();
    if (state.service == null) return;
    try {
      await state.refreshUtilization();
    } catch (_) {}
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    if (state.service == null) return;
    setState(() => _busy = true);
    try {
      await state.refreshHome();
      await _loadExtras(state);
    } on DsmException catch (e) {
      if (mounted) showToast(context, e.message, icon: Icons.error_outline_rounded);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadExtras(AppState state) async {
    final widgets = state.homeWidgets;
    final service = state.service!;
    if (widgets.contains(HomeWidgetType.transfers)) {
      try {
        _downloads = await _loadDownloads(state);
      } catch (_) {
        _downloads = [];
      }
    }
    if (widgets.contains(HomeWidgetType.packages)) {
      try {
        _packages = await service.packages();
      } catch (_) {
        _packages = [];
      }
    }
    if (widgets.contains(HomeWidgetType.logs)) {
      try {
        _logs = (await service.logs()).take(3).toList();
      } catch (_) {
        _logs = [];
      }
    }
    if (widgets.contains(HomeWidgetType.network)) {
      try {
        _network = await service.networkInfo();
      } catch (_) {
        _network = null;
      }
    }
    if (widgets.contains(HomeWidgetType.recentFiles)) {
      try {
        _recentFiles = await _loadRecent(service);
      } catch (_) {
        _recentFiles = [];
      }
    }
    if (widgets.contains(HomeWidgetType.photos)) {
      _photos = await _loadPhotos(state);
    }
    if (widgets.contains(HomeWidgetType.docker)) {
      try {
        _dockerContainers = await service.dockerContainers();
      } catch (_) {
        _dockerContainers = [];
      }
    }
    if (mounted) setState(() {});
  }

  Future<List<DownloadTask>> _loadDownloads(AppState state) async {
    final tool = state.activeTool;
    if (tool == null) return const [];
    final adapter = adapterFor(tool, state.service);
    try {
      return await adapter.list();
    } finally {
      adapter.dispose();
    }
  }

  Future<List<FileEntry>> _loadRecent(DsmService service) async {
    final shares = await service.shares();
    final files = <FileEntry>[];
    for (final share in shares.take(3)) {
      try {
        final entries = await service.files(share.path);
        files.addAll(entries.where((e) => !e.isDir));
      } catch (_) {}
    }
    files.sort((a, b) => (b.mtime ?? DateTime(0)).compareTo(a.mtime ?? DateTime(0)));
    return files.take(4).toList();
  }

  Future<List<PhotoItem>> _loadPhotos(AppState state) async {
    final source = state.photoSource;
    if (!source.configured) return const [];
    try {
      if (source.type == PhotoSourceType.folder) {
        return (await state.service!.folderPhotoPage(source.folderPath, limit: 12)).take(6).toList();
      }
      if (source.type == PhotoSourceType.synologyPhotos) {
        return (await state.service!.synologyPhotoItems(limit: 6));
      }
      if (source.type == PhotoSourceType.immich) {
        final client = ImmichClient(url: source.immichUrl, apiKey: source.immichKey);
        try {
          return (await client.search(page: 1, size: 6)).take(6).toList();
        } finally {
          client.dispose();
        }
      }
    } catch (_) {}
    return const [];
  }

  Future<void> _removeWidget(HomeWidgetType type) async {
    await context.read<AppState>().toggleHomeWidget(type, false);
    if (mounted) setState(() {});
  }

  Future<void> _addWidget(HomeWidgetType type) async {
    Navigator.pop(context);
    await context.read<AppState>().toggleHomeWidget(type, true);
    await _load();
  }

  void _openAddWidgets() {
    final state = context.read<AppState>();
    final available = HomeWidgetType.values.where((t) => !state.homeWidgets.contains(t)).toList();
    showAppSheet(
      context,
      title: '添加首页组件',
      subtitle: available.isEmpty ? '所有组件都已经在首页了' : '选择要显示在首页的卡片',
      children: [
        for (final type in available)
          SheetAction(
            icon: _meta(type).icon,
            iconColor: _meta(type).color,
            label: _meta(type).label,
            subtitle: _meta(type).description,
            onTap: () => _addWidget(type),
          ),
        if (available.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('你已经添加了全部组件。', style: context.texts.bodySmall?.copyWith(color: context.colors.textTertiary)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.colors;
    final storage = state.storage;
    final util = state.utilization;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PageScaffold(
        child: RefreshIndicator(
          onRefresh: _load,
          edgeOffset: 8,
          color: c.primary,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 132),
            children: [
              Entrance(
                index: 0,
                child: _TopBar(
                  editing: _editing,
                  onAvatar: () => widget.onOpenTab(4),
                  onSearch: () => _showSearchHint(context),
                  onTransfers: () => widget.onOpenTab(2),
                  onBell: () => _showNotice(context),
                  onEdit: () => setState(() => _editing = !_editing),
                ),
              ),
              const SizedBox(height: 20),
              Entrance(index: 1, child: _DeviceHeader(state: state)),
              const SizedBox(height: 24),
              if (!_editing) Entrance(index: 2, child: _QuickGrid(onOpenTab: widget.onOpenTab)),
              if (!_editing) const SizedBox(height: 20),
              for (var i = 0; i < state.homeWidgets.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Entrance(
                    index: 3 + i,
                    child: _buildWidget(state, state.homeWidgets[i], storage, util),
                  ),
                ),
              if (_editing)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 10),
                  child: OutlinedButton.icon(
                    onPressed: _openAddWidgets,
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('添加组件'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      side: BorderSide(color: c.primary.withValues(alpha: 0.35)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              if (state.homeWidgets.isEmpty)
                EmptyHint(
                  icon: Icons.dashboard_customize_rounded,
                  title: '首页还没有组件',
                  subtitle: '点击右上角编辑按钮，或添加一个组件',
                  action: FilledButton(onPressed: _openAddWidgets, child: const Text('添加组件')),
                ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  _busy ? '正在同步设备状态…' : '刚刚更新 · ${_clock(util?.sampledAt)}',
                  style: context.texts.labelSmall?.copyWith(color: c.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWidget(AppState state, HomeWidgetType type, StorageSnapshot? storage, Utilization? util) {
    final child = switch (type) {
      HomeWidgetType.resource => _ResourceCard(
          utilization: util,
          storage: storage,
          systemInfo: state.systemInfo,
          error: state.utilizationError,
          onOpen: () => Navigator.of(context).push(appRoute(const MonitorPage())),
          onRetry: () => state.refreshUtilization(),
        ),
      HomeWidgetType.storage => _StorageCard(
          storage: storage,
          onOpen: () => Navigator.of(context).push(appRoute(const StoragePage())),
        ),
      HomeWidgetType.transfers => _TransferCard(
          tasks: _downloads.where((t) => !t.isFinished).toList(),
          onOpen: () => widget.onOpenTab(2),
        ),
      HomeWidgetType.overview => _OverviewCard(
          info: state.systemInfo,
          onOpen: () => widget.onOpenTab(4),
        ),
      HomeWidgetType.network => _NetworkCard(
          network: _network,
          utilization: util,
          onOpen: () => widget.onOpenTab(4),
        ),
      HomeWidgetType.disks => _DisksCard(
          storage: storage,
          onOpen: () => Navigator.of(context).push(appRoute(const StoragePage())),
        ),
      HomeWidgetType.recentFiles => _RecentFilesCard(
          files: _recentFiles,
          onOpen: () {
            if (_recentFiles.isEmpty) return;
            final parent = _recentFiles.first.path.substring(0, _recentFiles.first.path.lastIndexOf('/'));
            Navigator.of(context).push(appRoute(FilesBrowserPage(initialPath: parent)));
          },
        ),
      HomeWidgetType.quickActions => _QuickActionsCard(
          onShutdown: () => _powerAction('shutdown'),
          onReboot: () => _powerAction('reboot'),
          onOpenWeb: () => _openWeb(),
        ),
      HomeWidgetType.photos => _PhotosCard(
          photos: _photos,
          configured: state.photoSource.configured,
          onOpen: () => Navigator.of(context).push(appRoute(const PhotosPage())),
        ),
      HomeWidgetType.packages => _PackagesCard(
          packages: _packages,
          onOpen: () => widget.onOpenTab(3),
        ),
      HomeWidgetType.logs => _LogsCard(
          logs: _logs,
          onOpen: () => Navigator.of(context).push(appRoute(const LogsPage())),
        ),
      HomeWidgetType.docker => _DockerCard(
          containers: _dockerContainers,
          onOpen: () => Navigator.of(context).push(appRoute(const DockerPage())),
        ),
    };

    if (!_editing) return child;
    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            top: -8,
            right: -8,
            child: GestureDetector(
              onTap: () => _removeWidget(type),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  shape: BoxShape.circle,
                  boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3))],
                ),
                child: const Icon(Icons.remove_rounded, size: 18, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _powerAction(String action) async {
    final isShutdown = action == 'shutdown';
    final ok = await showConfirm(
      context,
      title: isShutdown ? '确认关闭群晖？' : '确认重启群晖？',
      message: isShutdown ? '设备将安全关机，之后需要手动开机。' : '设备将在约 2 分钟后重新上线。',
      confirmText: isShutdown ? '关机' : '重启',
      danger: true,
    );
    if (!ok) return;
    try {
      await context.read<AppState>().service!.power(action);
      if (mounted) showToast(context, isShutdown ? '已发送关机指令' : '已发送重启指令');
    } on DsmException catch (e) {
      if (mounted) showToast(context, e.message, icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _openWeb() async {
    final server = context.read<AppState>().server;
    if (server == null) return;
    await launchUrl(Uri.parse(server.baseUrl), mode: LaunchMode.externalApplication);
  }

  String _clock(DateTime? time) {
    if (time == null) return '—';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  void _showSearchHint(BuildContext context) {
    showAppSheet(
      context,
      title: '全局搜索',
      subtitle: '选择要搜索的位置',
      children: [
        SheetAction(
          icon: Icons.folder_open_rounded,
          label: '在文件中搜索',
          subtitle: '进入文件页按文件名搜索',
          onTap: () {
            Navigator.pop(context);
            widget.onOpenTab(1);
          },
        ),
        SheetAction(
          icon: Icons.apps_rounded,
          label: '在应用中心搜索',
          subtitle: '查找已安装的套件',
          onTap: () {
            Navigator.pop(context);
            widget.onOpenTab(3);
          },
        ),
        SheetAction(
          icon: Icons.photo_library_rounded,
          label: '打开相册',
          subtitle: '浏览 DSM / Synology Photos / Immich',
          onTap: () {
            Navigator.pop(context);
            Navigator.of(context).push(appRoute(const PhotosPage()));
          },
        ),
      ],
    );
  }

  void _showNotice(BuildContext context) {
    final storage = context.read<AppState>().storage;
    final volumes = storage?.volumes ?? const <VolumeInfo>[];
    final abnormal = volumes.where((v) => v.status.isNotEmpty && v.status != 'normal').toList();
    final healthy = abnormal.isEmpty;
    showAppSheet(
      context,
      title: '设备消息',
      subtitle: '来自群晖的系统通知',
      children: [
        SoftCard(
          shadow: false,
          padding: const EdgeInsets.all(14),
          color: context.colors.surfaceAlt,
          child: Row(
            children: [
              Icon(healthy ? Icons.verified_rounded : Icons.warning_amber_rounded, size: 20, color: healthy ? context.colors.success : context.colors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  healthy
                      ? (volumes.isEmpty ? '设备已连接，等待读取存储状态。' : '${volumes.length} 个存储空间状态正常，SMART 检测通过。')
                      : '${abnormal.first.name} 状态异常：${abnormal.first.status}',
                  style: context.texts.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  final bool editing;
  final VoidCallback onAvatar;
  final VoidCallback onSearch;
  final VoidCallback onTransfers;
  final VoidCallback onBell;
  final VoidCallback onEdit;
  const _TopBar({
    required this.editing,
    required this.onAvatar,
    required this.onSearch,
    required this.onTransfers,
    required this.onBell,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.colors;
    return Row(
      children: [
        GestureDetector(
          onTap: onAvatar,
          child: UserAvatar(
            account: state.server?.account ?? '?',
            imagePath: state.customAvatarPath,
            size: 42,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: SearchPill(onTap: onSearch, hint: '搜索文件、套件')),
        const SizedBox(width: 4),
        if (editing)
          TextButton(
            onPressed: onEdit,
            child: Text('完成', style: context.texts.labelLarge?.copyWith(color: c.primary)),
          )
        else ...[
          CircleIconButton(icon: Icons.swap_vert_rounded, onTap: onTransfers),
          const SizedBox(width: 2),
          Badge(
            backgroundColor: c.danger,
            smallSize: 7,
            padding: EdgeInsets.zero,
            offset: const Offset(-3, 4),
            child: CircleIconButton(icon: Icons.notifications_none_rounded, onTap: onBell),
          ),
          const SizedBox(width: 2),
          CircleIconButton(icon: Icons.edit_rounded, onTap: onEdit, size: 20),
        ],
      ],
    );
  }
}

class _DeviceHeader extends StatelessWidget {
  final AppState state;
  const _DeviceHeader({required this.state});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final info = state.systemInfo;
    final name = state.deviceTitle;
    final lan = isLanAddress(state.server?.host ?? '');
    final version = info == null ? '正在读取设备信息' : '${info.model} · DSM ${info.dsmLabel}';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConnectionStatus(online: state.online, latencyMs: state.latencyMs, lan: lan),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _showDeviceSheet(context),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(name, style: context.texts.displayMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 2),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Icon(Icons.chevron_right_rounded, size: 26, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(version, style: context.texts.bodySmall?.copyWith(color: c.textTertiary, fontSize: 12.5)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const NasDevice(width: 86),
      ],
    );
  }

  void _showDeviceSheet(BuildContext context) {
    final info = state.systemInfo;
    showAppSheet(
      context,
      title: state.server?.displayName ?? name,
      subtitle: state.server == null ? null : '${state.server!.account}@${state.server!.host}:${state.server!.port}',
      children: [
        SoftCard(
          shadow: false,
          color: context.colors.surfaceAlt,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              InfoRow(label: '设备名称', value: name),
              InfoRow(label: '型号', value: info?.model ?? '—'),
              InfoRow(label: 'DSM 版本', value: info?.dsmLabel ?? '—'),
              InfoRow(label: '运行时间', value: info == null ? '—' : formatUptime(info.uptime)),
              InfoRow(label: 'CPU 温度', value: info == null || info.temperature <= 0 ? '无法获取' : '${info.temperature.toStringAsFixed(0)} °C'),
              InfoRow(label: '序列号', value: (info?.serial.isNotEmpty ?? false) ? info!.serial : '—'),
            ],
          ),
        ),
      ],
    );
  }

  String get name => state.deviceTitle;
}

class _QuickGrid extends StatelessWidget {
  final void Function(int) onOpenTab;
  const _QuickGrid({required this.onOpenTab});

  @override
  Widget build(BuildContext context) {
    final items = <_QuickItem>[
      _QuickItem(label: '文件管理', icon: Icons.folder_rounded, colors: const [Color(0xFF63B3FF), Color(0xFF2E7BFF)], onTap: () => onOpenTab(1)),
      _QuickItem(label: '下载', icon: Icons.download_rounded, colors: const [Color(0xFF4BE0A8), Color(0xFF16C08E)], onTap: () => onOpenTab(2)),
      _QuickItem(
        label: '相册',
        icon: Icons.photo_library_rounded,
        colors: const [Color(0xFFB59BFF), Color(0xFF8A6BFF)],
        onTap: () => Navigator.of(context).push(appRoute(const PhotosPage())),
      ),
      _QuickItem(label: '套件中心', icon: Icons.storefront_rounded, colors: const [Color(0xFF5B9BFF), Color(0xFF3A6FF5)], onTap: () => onOpenTab(3)),
      _QuickItem(
        label: '资源监控',
        icon: Icons.monitor_heart_rounded,
        colors: const [Color(0xFF3F4A63), Color(0xFF222A3C)],
        onTap: () => Navigator.of(context).push(appRoute(const MonitorPage())),
      ),
      _QuickItem(
        label: '存储空间',
        icon: Icons.storage_rounded,
        colors: const [Color(0xFF55DFC4), Color(0xFF20BFA2)],
        onTap: () => Navigator.of(context).push(appRoute(const StoragePage())),
      ),
      _QuickItem(
        label: '日志',
        icon: Icons.receipt_long_rounded,
        colors: const [Color(0xFFFFD36E), Color(0xFFFFB020)],
        onTap: () => Navigator.of(context).push(appRoute(const LogsPage())),
      ),
      _QuickItem(
        label: '用户',
        icon: Icons.group_rounded,
        colors: const [Color(0xFFFFA1B8), Color(0xFFFF6E93)],
        onTap: () => Navigator.of(context).push(appRoute(const UsersPage())),
      ),
      _QuickItem(
        label: '共享链接',
        icon: Icons.link_rounded,
        colors: const [Color(0xFF6FC8FF), Color(0xFF2E9BF0)],
        onTap: () => Navigator.of(context).push(appRoute(const SharedLinksPage())),
      ),
      _QuickItem(
        label: 'Docker',
        icon: Icons.widgets_rounded,
        colors: const [Color(0xFF3DA9FC), Color(0xFF2496ED)],
        onTap: () => Navigator.of(context).push(appRoute(const DockerPage())),
      ),
    ];

    return GridView.count(
      crossAxisCount: 5,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      mainAxisSpacing: 16,
      crossAxisSpacing: 4,
      childAspectRatio: 0.78,
      children: [
        for (final item in items)
          GestureDetector(
            onTap: item.onTap,
            behavior: HitTestBehavior.opaque,
            child: Column(
              children: [
                AppIconTile(icon: item.icon, colors: item.colors, size: 54),
                const SizedBox(height: 7),
                Text(
                  item.label,
                  style: context.texts.labelMedium?.copyWith(fontSize: 11.5, color: context.colors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _QuickItem {
  final String label;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
  const _QuickItem({required this.label, required this.icon, required this.colors, required this.onTap});
}

class _WidgetMeta {
  final String label;
  final String description;
  final IconData icon;
  final Color color;
  const _WidgetMeta(this.label, this.description, this.icon, this.color);
}

_WidgetMeta _meta(HomeWidgetType type) => switch (type) {
      HomeWidgetType.resource => const _WidgetMeta('资源监控', 'CPU / 内存 / 存储 / 网络 / 硬盘', Icons.monitor_heart_rounded, Color(0xFF3D7BFF)),
      HomeWidgetType.storage => const _WidgetMeta('存储空间', '各存储空间的容量与使用率', Icons.storage_rounded, Color(0xFF28BFA2)),
      HomeWidgetType.transfers => const _WidgetMeta('传输任务', '下载中的任务与实时速度', Icons.swap_vert_rounded, Color(0xFF16C08E)),
      HomeWidgetType.overview => const _WidgetMeta('系统概览', '型号、DSM 版本、运行时间与温度', Icons.dns_rounded, Color(0xFF5B84F7)),
      HomeWidgetType.network => const _WidgetMeta('网络状态', '网口 IP、上下行速度与连接信息', Icons.lan_rounded, Color(0xFF4FA8FF)),
      HomeWidgetType.disks => const _WidgetMeta('硬盘健康', '硬盘温度与 SMART 状态', Icons.storage_rounded, Color(0xFFFFB020)),
      HomeWidgetType.recentFiles => const _WidgetMeta('最近文件', '最近修改的文件，快速打开', Icons.history_rounded, Color(0xFF8A6BFF)),
      HomeWidgetType.quickActions => const _WidgetMeta('快捷操作', '关机、重启与打开 DSM', Icons.bolt_rounded, Color(0xFFFF8F2E)),
      HomeWidgetType.photos => const _WidgetMeta('相册预览', '显示相册里最近的几张照片', Icons.photo_library_rounded, Color(0xFFFF6E93)),
      HomeWidgetType.packages => const _WidgetMeta('套件状态', '运行中的套件与数量', Icons.apps_rounded, Color(0xFF6C8BFF)),
      HomeWidgetType.logs => const _WidgetMeta('最新日志', '最近几条系统日志', Icons.receipt_long_rounded, Color(0xFF8A96AE)),
      HomeWidgetType.docker => const _WidgetMeta('Docker 容器', '容器运行状态与快捷操作', Icons.widgets_rounded, Color(0xFF2496ED)),
    };

class _WidgetCardHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final String? action;
  final VoidCallback? onAction;
  const _WidgetCardHeader({required this.title, required this.icon, required this.color, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return SectionHeader(title: title, icon: icon, iconColor: color, iconBg: color.withValues(alpha: 0.12), action: action, onAction: onAction);
  }
}

// ---------- 组件卡片 ----------

class _ResourceCard extends StatelessWidget {
  final Utilization? utilization;
  final StorageSnapshot? storage;
  final SystemInfo? systemInfo;
  final String? error;
  final VoidCallback onOpen;
  final VoidCallback onRetry;
  const _ResourceCard({
    required this.utilization,
    required this.storage,
    required this.systemInfo,
    required this.error,
    required this.onOpen,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final util = utilization;
    final memGb = util == null || util.memUsedBytes <= 0 ? '—' : (util.memUsedBytes / 1024 / 1024 / 1024).toStringAsFixed(1);
    final diskTemps = storage?.disks.where((d) => d.temperature > 0).toList() ?? const <DiskInfo>[];
    final avgDiskTemp = diskTemps.isEmpty ? null : diskTemps.map((e) => e.temperature).reduce((a, b) => a + b) / diskTemps.length;
    final cpuTemp = systemInfo?.temperature ?? 0;
    final unavailable = util == null && error != null;

    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetCardHeader(title: '资源监控', icon: Icons.monitor_heart_rounded, color: const Color(0xFF3D7BFF), action: '详情', onAction: onOpen),
          const SizedBox(height: 18),
          if (unavailable)
            Column(
              children: [
                Icon(Icons.signal_wifi_statusbar_null_rounded, size: 34, color: c.textTertiary),
                const SizedBox(height: 8),
                Text('无法获取资源监控数据', style: context.texts.titleSmall?.copyWith(color: c.textSecondary)),
                const SizedBox(height: 4),
                Text(error!, textAlign: TextAlign.center, style: context.texts.labelSmall?.copyWith(color: c.textTertiary)),
                const SizedBox(height: 10),
                OutlinedButton(onPressed: onRetry, child: const Text('重试')),
              ],
            )
          else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                RingGauge(value: (util?.cpuPercent ?? 0) / 100, label: 'CPU', size: 92, stroke: 7.5, valueText: util == null ? '—' : null),
                RingGauge(
                  value: (util?.memPercent ?? 0) / 100,
                  label: '内存',
                  size: 92,
                  stroke: 7.5,
                  valueText: memGb,
                  subText: memGb == '—' ? null : 'GB · ${util!.memPercent.toStringAsFixed(0)}%',
                  color: const Color(0xFF6C8BFF),
                  endColor: const Color(0xFF8FA5FF),
                ),
                RingGauge(
                  value: storage?.ratio ?? 0,
                  label: '存储',
                  size: 92,
                  stroke: 7.5,
                  color: const Color(0xFF32C8A2),
                  endColor: const Color(0xFF5BE3BE),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(title: '网络', children: [
                    _MiniStatLine(icon: Icons.arrow_upward_rounded, value: util == null ? '—' : formatSpeed(util.netTx, compact: true)),
                    _MiniStatLine(icon: Icons.arrow_downward_rounded, value: util == null ? '—' : formatSpeed(util.netRx, compact: true)),
                  ]),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MiniStat(title: '硬盘', children: [
                    _MiniStatLine(label: '读', value: util == null ? '—' : formatSpeed(util.diskRead, compact: true)),
                    _MiniStatLine(label: '写', value: util == null ? '—' : formatSpeed(util.diskWrite, compact: true)),
                  ]),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MiniStat(title: '温度', children: [
                    _MiniStatLine(label: 'CPU', value: cpuTemp > 0 ? '${cpuTemp.toStringAsFixed(0)}°C' : '无法获取'),
                    _MiniStatLine(label: '硬盘', value: avgDiskTemp == null ? '无法获取' : '${avgDiskTemp.toStringAsFixed(0)}°C'),
                  ]),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _MiniStat({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.texts.titleSmall?.copyWith(fontSize: 13.5)),
          const SizedBox(height: 7),
          ...children,
        ],
      ),
    );
  }
}

class _MiniStatLine extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final String value;
  const _MiniStatLine({this.label, this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          if (icon != null)
            Icon(icon, size: 11, color: c.textTertiary)
          else
            SizedBox(width: 22, child: Text(label ?? '', style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5))),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              value,
              style: tabular(context.texts.bodySmall?.copyWith(fontSize: 10.5, color: c.textSecondary)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageCard extends StatelessWidget {
  final StorageSnapshot? storage;
  final VoidCallback onOpen;
  const _StorageCard({required this.storage, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final volumes = storage?.volumes ?? const <VolumeInfo>[];
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetCardHeader(title: '存储空间', icon: Icons.storage_rounded, color: const Color(0xFF28BFA2), action: '管理', onAction: onOpen),
          const SizedBox(height: 14),
          if (volumes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('无法获取存储空间信息', style: context.texts.bodySmall?.copyWith(color: c.textTertiary)),
            )
          else
            for (var i = 0; i < volumes.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              _VolumeRow(volume: volumes[i]),
            ],
        ],
      ),
    );
  }
}

class _VolumeRow extends StatelessWidget {
  final VolumeInfo volume;
  const _VolumeRow({required this.volume});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final percent = (volume.ratio * 100).toStringAsFixed(0);
    final warn = volume.ratio > 0.85;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.dns_rounded, size: 16, color: c.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(volume.name, style: context.texts.titleSmall?.copyWith(fontSize: 14)),
                  const SizedBox(height: 2),
                  Text('${formatBytes(volume.used)} / ${formatBytes(volume.total)}', style: tabular(context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 11))),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: (warn ? c.warning : c.success).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
              child: Text('$percent%', style: tabular(context.texts.labelSmall?.copyWith(color: warn ? c.warning : c.success, fontSize: 11))),
            ),
          ],
        ),
        const SizedBox(height: 9),
        SoftProgressBar(
          value: volume.ratio,
          height: 6,
          colors: warn ? const [Color(0xFFFFB020), Color(0xFFFF8A3D)] : const [Color(0xFF2E6BFF), Color(0xFF63A0FF)],
        ),
      ],
    );
  }
}

class _TransferCard extends StatelessWidget {
  final List<DownloadTask> tasks;
  final VoidCallback onOpen;
  const _TransferCard({required this.tasks, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetCardHeader(title: '传输任务', icon: Icons.swap_vert_rounded, color: const Color(0xFF16C08E), action: '全部', onAction: onOpen),
          const SizedBox(height: 14),
          if (tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('当前没有进行中的传输任务', style: context.texts.bodySmall?.copyWith(color: c.textTertiary)),
            )
          else
            for (var i = 0; i < tasks.length && i < 2; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Text(tasks[i].title, style: context.texts.titleSmall?.copyWith(fontSize: 13.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  Text('${(tasks[i].progress * 100).toStringAsFixed(0)}%', style: tabular(context.texts.labelLarge?.copyWith(color: c.primary, fontSize: 12))),
                ],
              ),
              const SizedBox(height: 6),
              SoftProgressBar(value: tasks[i].progress, height: 5),
              const SizedBox(height: 5),
              Row(
                children: [
                  Text(tasks[i].statusLabel, style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5)),
                  const Spacer(),
                  Text(
                    '${formatSpeed(tasks[i].speedDownload)} · ${formatBytes(tasks[i].downloaded)} / ${formatBytes(tasks[i].size)}',
                    style: tabular(context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5)),
                  ),
                ],
              ),
            ],
        ],
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  final SystemInfo? info;
  final VoidCallback onOpen;
  const _OverviewCard({required this.info, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetCardHeader(title: '系统概览', icon: Icons.dns_rounded, color: const Color(0xFF5B84F7), action: '设置', onAction: onOpen),
          const SizedBox(height: 8),
          InfoRow(label: '型号', value: info?.model.isNotEmpty == true ? info!.model : '—'),
          Divider(height: 1, color: c.border.withValues(alpha: 0.6)),
          InfoRow(label: 'DSM 版本', value: info?.dsmLabel.isNotEmpty == true ? info!.dsmLabel : '—'),
          Divider(height: 1, color: c.border.withValues(alpha: 0.6)),
          InfoRow(label: '运行时间', value: info == null ? '—' : formatUptime(info!.uptime)),
          Divider(height: 1, color: c.border.withValues(alpha: 0.6)),
          InfoRow(label: 'CPU 温度', value: info == null || info!.temperature <= 0 ? '无法获取' : '${info!.temperature.toStringAsFixed(0)} °C'),
          Divider(height: 1, color: c.border.withValues(alpha: 0.6)),
          InfoRow(label: '内存', value: info == null || info!.ramMb == 0 ? '—' : formatBytes(info!.ramMb * 1024 * 1024)),
        ],
      ),
    );
  }
}

class _NetworkCard extends StatelessWidget {
  final Map<String, dynamic>? network;
  final Utilization? utilization;
  final VoidCallback onOpen;
  const _NetworkCard({required this.network, required this.utilization, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final interfaces = <Map<String, dynamic>>[];
    final raw = network?['interfaces'] ?? network?['ifaces'] ?? network?['adapters'];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) interfaces.add(item.cast<String, dynamic>());
      }
    }
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetCardHeader(title: '网络状态', icon: Icons.lan_rounded, color: const Color(0xFF4FA8FF), action: '设置', onAction: onOpen),
          const SizedBox(height: 12),
          if (interfaces.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('无法获取网络接口信息', style: context.texts.bodySmall?.copyWith(color: c.textTertiary)),
            )
          else
            for (final item in interfaces.take(2))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(11)),
                      child: Icon(Icons.settings_ethernet_rounded, size: 17, color: c.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item['name'] ?? item['ifname'] ?? '接口'} · ${item['ip'] ?? item['ipv4'] ?? '—'}',
                            style: context.texts.titleSmall?.copyWith(fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${item['speed'] ?? item['max_speed'] ?? ''}${item['mac'] != null ? ' · ${item['mac']}' : ''}',
                            style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(13)),
            child: Row(
              children: [
                Icon(Icons.arrow_downward_rounded, size: 13, color: c.textTertiary),
                const SizedBox(width: 3),
                Text(utilization == null ? '—' : formatSpeed(utilization!.netRx), style: tabular(context.texts.labelSmall?.copyWith(color: c.textSecondary, fontSize: 11))),
                const SizedBox(width: 14),
                Icon(Icons.arrow_upward_rounded, size: 13, color: c.textTertiary),
                const SizedBox(width: 3),
                Text(utilization == null ? '—' : formatSpeed(utilization!.netTx), style: tabular(context.texts.labelSmall?.copyWith(color: c.textSecondary, fontSize: 11))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DisksCard extends StatelessWidget {
  final StorageSnapshot? storage;
  final VoidCallback onOpen;
  const _DisksCard({required this.storage, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final disks = storage?.disks ?? const <DiskInfo>[];
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetCardHeader(title: '硬盘健康', icon: Icons.storage_rounded, color: const Color(0xFFFFB020), action: '详情', onAction: onOpen),
          const SizedBox(height: 8),
          if (disks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('无法获取硬盘信息', style: context.texts.bodySmall?.copyWith(color: c.textTertiary)),
            )
          else
            for (var i = 0; i < disks.length; i++) ...[
              if (i > 0) Divider(height: 1, color: c.border.withValues(alpha: 0.55)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Icon(Icons.storage_rounded, size: 16, color: c.textTertiary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(disks[i].id.toUpperCase(), style: context.texts.titleSmall?.copyWith(fontSize: 12.5))),
                    Text(disks[i].temperature > 0 ? '${disks[i].temperature.toStringAsFixed(0)}°C' : '温度无法获取',
                        style: context.texts.labelSmall?.copyWith(color: disks[i].temperature > 0 ? c.textSecondary : c.textTertiary, fontSize: 10.5)),
                    const SizedBox(width: 8),
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: disks[i].status == 'normal' ? c.success : c.warning, shape: BoxShape.circle)),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }
}

class _RecentFilesCard extends StatelessWidget {
  final List<FileEntry> files;
  final VoidCallback onOpen;
  const _RecentFilesCard({required this.files, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetCardHeader(title: '最近文件', icon: Icons.history_rounded, color: const Color(0xFF8A6BFF), action: '文件', onAction: onOpen),
          const SizedBox(height: 8),
          if (files.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('最近没有修改过的文件', style: context.texts.bodySmall?.copyWith(color: c.textTertiary)),
            )
          else
            for (final file in files)
              FileEntryTile(
                entry: file,
                showMore: false,
                onTap: onOpen,
                trailing: Icon(Icons.chevron_right_rounded, size: 16, color: c.textTertiary.withValues(alpha: 0.7)),
              ),
        ],
      ),
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  final VoidCallback onShutdown;
  final VoidCallback onReboot;
  final VoidCallback onOpenWeb;
  const _QuickActionsCard({required this.onShutdown, required this.onReboot, required this.onOpenWeb});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetCardHeader(title: '快捷操作', icon: Icons.bolt_rounded, color: const Color(0xFFFF8F2E)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ActionTile(icon: Icons.open_in_new_rounded, label: '打开 DSM', color: c.primary, onTap: onOpenWeb),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionTile(icon: Icons.restart_alt_rounded, label: '重启', color: const Color(0xFF5B84F7), onTap: onReboot),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionTile(icon: Icons.power_settings_new_rounded, label: '关机', color: c.danger, onTap: onShutdown),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionTile({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 6),
            Text(label, style: context.texts.labelSmall?.copyWith(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _PhotosCard extends StatelessWidget {
  final List<PhotoItem> photos;
  final bool configured;
  final VoidCallback onOpen;
  const _PhotosCard({required this.photos, required this.configured, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetCardHeader(title: '相册', icon: Icons.photo_library_rounded, color: const Color(0xFFFF6E93), action: configured ? '查看全部' : '设置', onAction: onOpen),
          const SizedBox(height: 12),
          if (photos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                configured ? '相册里还没有照片' : '还没有设置相册来源，点击这里选择目录或接入 Immich',
                style: context.texts.bodySmall?.copyWith(color: c.textTertiary),
              ),
            )
          else
            SizedBox(
              height: 86,
              child: Row(
                children: [
                  for (var i = 0; i < photos.length && i < 4; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: photos[i].thumbUrl.isEmpty
                            ? Container(color: c.surfaceAlt, child: Icon(Icons.image_rounded, size: 22, color: c.textTertiary))
                            : Image.network(
                                photos[i].thumbUrl,
                                headers: photos[i].headers,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(color: c.surfaceAlt, child: Icon(Icons.broken_image_rounded, size: 20, color: c.textTertiary)),
                              ),
                      ),
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

class _PackagesCard extends StatelessWidget {
  final List<DsmPackage> packages;
  final VoidCallback onOpen;
  const _PackagesCard({required this.packages, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final running = packages.where((p) => p.isRunning).toList();
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetCardHeader(title: '套件状态', icon: Icons.apps_rounded, color: const Color(0xFF6C8BFF), action: '管理', onAction: onOpen),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('${running.length}', style: tabular(context.texts.displayLarge?.copyWith(fontSize: 30))),
              const SizedBox(width: 6),
              Text('/ ${packages.length} 个运行中', style: context.texts.bodySmall?.copyWith(color: c.textTertiary)),
            ],
          ),
          if (running.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final pkg in running.take(5))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(9)),
                    child: Text(pkg.displayName, style: context.texts.labelSmall?.copyWith(fontSize: 10.5, color: c.textSecondary)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LogsCard extends StatelessWidget {
  final List<LogEntry> logs;
  final VoidCallback onOpen;
  const _LogsCard({required this.logs, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetCardHeader(title: '最新日志', icon: Icons.receipt_long_rounded, color: const Color(0xFF8A96AE), action: '全部', onAction: onOpen),
          const SizedBox(height: 8),
          if (logs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('还没有日志记录', style: context.texts.bodySmall?.copyWith(color: c.textTertiary)),
            )
          else
            for (var i = 0; i < logs.length; i++) ...[
              if (i > 0) Divider(height: 1, color: c.border.withValues(alpha: 0.5)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.circle, size: 6, color: c.textTertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(logs[i].what.isEmpty ? '系统事件' : logs[i].what, style: context.texts.bodySmall?.copyWith(color: c.textSecondary, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Text(logs[i].time, style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 9.5)),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }
}

class _DockerCard extends StatelessWidget {
  final List<DockerContainer> containers;
  final VoidCallback onOpen;
  const _DockerCard({required this.containers, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final running = containers.where((item) => item.isRunning).toList();
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetCardHeader(title: 'Docker 容器', icon: Icons.widgets_rounded, color: const Color(0xFF2496ED), action: '管理', onAction: onOpen),
          const SizedBox(height: 10),
          if (containers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('没有读取到容器，或未安装 Container Manager', style: context.texts.bodySmall?.copyWith(color: c.textTertiary)),
            )
          else ...[
            Row(
              children: [
                Text('${running.length}', style: tabular(context.texts.displayLarge?.copyWith(fontSize: 28))),
                const SizedBox(width: 6),
                Text('/ ${containers.length} 个运行中', style: context.texts.bodySmall?.copyWith(color: c.textTertiary)),
              ],
            ),
            if (containers.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final container in containers.take(3))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: container.isRunning ? c.success : (container.isError ? c.danger : c.textTertiary),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(child: Text(container.name, style: context.texts.bodySmall?.copyWith(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Text(container.statusLabel, style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10)),
                    ],
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}