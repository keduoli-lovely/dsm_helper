import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../dsm/dsm_client.dart';
import '../dsm/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icon_tile.dart';
import '../widgets/feedback.dart';
import '../widgets/nas_device.dart';
import '../widgets/nav_bar.dart';
import '../widgets/surfaces.dart';
import '../widgets/ui_kit.dart';
import 'files_browser_page.dart';
import 'logs_page.dart';
import 'monitor_page.dart';
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
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshUtilization());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
    }
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
      try {
        final downloads = await state.service!.downloads();
        if (mounted) setState(() => _downloads = downloads);
      } catch (_) {
        // 未安装 Download Station 时不打扰用户
      }
    } on DsmException catch (e) {
      if (mounted) showToast(context, e.message, icon: Icons.error_outline_rounded);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.colors;
    final info = state.systemInfo;
    final storage = state.storage;
    final util = state.utilization;
    final activeDownloads = _downloads.where((t) => t.isActive).toList();

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
                  onAvatar: () => widget.onOpenTab(4),
                  onSearch: () => _showSearchHint(context),
                  onTransfers: () => widget.onOpenTab(2),
                  onBell: () => _showNotice(context),
                ),
              ),
              const SizedBox(height: 20),
              Entrance(index: 1, child: _DeviceHeader(state: state)),
              const SizedBox(height: 24),
              Entrance(index: 2, child: _QuickGrid(onOpenTab: widget.onOpenTab)),
              const SizedBox(height: 20),
              Entrance(
                index: 3,
                child: _ResourceCard(
                  utilization: util,
                  storage: storage,
                  systemInfo: info,
                  onOpen: () => Navigator.of(context).push(appRoute(const MonitorPage())),
                ),
              ),
              const SizedBox(height: 16),
              Entrance(
                index: 4,
                child: _StorageCard(
                  storage: storage,
                  onOpen: () => Navigator.of(context).push(appRoute(const StoragePage())),
                ),
              ),
              if (activeDownloads.isNotEmpty) ...[
                const SizedBox(height: 16),
                Entrance(
                  index: 5,
                  child: _TransferCard(
                    tasks: activeDownloads,
                    onOpen: () => widget.onOpenTab(2),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Entrance(
                index: 6,
                child: Center(
                  child: Text(
                    _busy ? '正在同步设备状态…' : '刚刚更新 · ${_clock(util?.sampledAt)}',
                    style: context.texts.labelSmall?.copyWith(color: c.textTertiary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
          icon: Icons.settings_rounded,
          label: '设备设置',
          subtitle: '存储、网络与电源控制',
          onTap: () {
            Navigator.pop(context);
            widget.onOpenTab(4);
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
              Icon(
                healthy ? Icons.verified_rounded : Icons.warning_amber_rounded,
                size: 20,
                color: healthy ? context.colors.success : context.colors.warning,
              ),
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
  final VoidCallback onAvatar;
  final VoidCallback onSearch;
  final VoidCallback onTransfers;
  final VoidCallback onBell;
  const _TopBar({required this.onAvatar, required this.onSearch, required this.onTransfers, required this.onBell});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.colors;
    return Row(
      children: [
        GestureDetector(
          onTap: onAvatar,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFC080), Color(0xFFFF9F73)],
              ),
              boxShadow: [
                BoxShadow(color: const Color(0xFFFFAE63).withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6)),
              ],
            ),
            child: Center(
              child: Text(
                state.accountInitial,
                style: context.texts.titleMedium?.copyWith(color: Colors.white, fontSize: 17),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: SearchPill(onTap: onSearch, hint: '搜索文件、套件')),
        const SizedBox(width: 6),
        CircleIconButton(icon: Icons.swap_vert_rounded, onTap: onTransfers),
        const SizedBox(width: 2),
        Badge(
          backgroundColor: c.danger,
          smallSize: 7,
          padding: EdgeInsets.zero,
          offset: const Offset(-3, 4),
          child: CircleIconButton(icon: Icons.notifications_none_rounded, onTap: onBell),
        ),
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
    final name = (info?.hostname.isNotEmpty ?? false)
        ? info!.hostname
        : (state.server?.note?.isNotEmpty ?? false)
            ? state.server!.note!
            : '我的群晖';
    final host = state.server?.host ?? '';
    final lan = isLanAddress(host);
    final https = state.server?.https ?? false;
    final version = info == null ? '正在读取设备信息' : '${info.model} · DSM ${info.dsmLabel}';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GlassBadge(
                    icon: lan ? Icons.wifi_rounded : Icons.public_rounded,
                    label: lan ? '局域网连接' : '远程连接',
                  ),
                  const SizedBox(width: 8),
                  Icon(https ? Icons.shield_rounded : Icons.lock_open_rounded, size: 12, color: https ? c.success : c.warning),
                  const SizedBox(width: 3),
                  Text(
                    https ? '已加密' : 'HTTP 直连',
                    style: context.texts.labelSmall?.copyWith(color: https ? c.textTertiary : c.warning, fontSize: 10.5),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _showDeviceSheet(context),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: context.texts.displayMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
      title: state.server?.displayName ?? '我的群晖',
      subtitle: state.server == null ? null : '${state.server!.account}@${state.server!.host}:${state.server!.port}',
      children: [
        SoftCard(
          shadow: false,
          color: context.colors.surfaceAlt,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              InfoRow(label: '型号', value: info?.model ?? '—'),
              InfoRow(label: 'DSM 版本', value: info?.dsmLabel ?? '—'),
              InfoRow(label: '运行时间', value: info == null ? '—' : formatUptime(info.uptime)),
              InfoRow(label: 'CPU 温度', value: info == null || info.temperature <= 0 ? '—' : '${info.temperature.toStringAsFixed(0)} °C'),
              InfoRow(label: '序列号', value: (info?.serial.isNotEmpty ?? false) ? info!.serial : '—'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SheetAction(icon: Icons.settings_rounded, label: '打开设备设置', onTap: () => Navigator.pop(context)),
      ],
    );
  }
}

class _QuickGrid extends StatelessWidget {
  final void Function(int) onOpenTab;
  const _QuickGrid({required this.onOpenTab});

  @override
  Widget build(BuildContext context) {
    final items = <_QuickItem>[
      _QuickItem(
        label: '文件管理',
        icon: Icons.folder_rounded,
        colors: const [Color(0xFF63B3FF), Color(0xFF2E7BFF)],
        onTap: () => onOpenTab(1),
      ),
      _QuickItem(
        label: '下载',
        icon: Icons.download_rounded,
        colors: const [Color(0xFF4BE0A8), Color(0xFF16C08E)],
        onTap: () => onOpenTab(2),
      ),
      _QuickItem(
        label: '相册',
        icon: Icons.photo_library_rounded,
        colors: const [Color(0xFFB59BFF), Color(0xFF8A6BFF)],
        onTap: () => Navigator.of(context).push(appRoute(const FilesBrowserPage(initialPath: '/photo'))),
      ),
      _QuickItem(
        label: '应用中心',
        icon: Icons.storefront_rounded,
        colors: const [Color(0xFF5B9BFF), Color(0xFF3A6FF5)],
        onTap: () => onOpenTab(3),
      ),
      _QuickItem(
        label: '资源监控',
        icon: Icons.monitor_heart_rounded,
        colors: const [Color(0xFF3F4A63), Color(0xFF222A3C)],
        onTap: () => Navigator.of(context).push(appRoute(const MonitorPage())),
      ),
      _QuickItem(
        label: '系统设置',
        icon: Icons.settings_rounded,
        colors: const [Color(0xFF9AA6BD), Color(0xFF6E7A91)],
        onTap: () => onOpenTab(4),
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
        label: '更多',
        icon: Icons.grid_view_rounded,
        colors: const [Color(0xFFB8C4DA), Color(0xFF8A96AE)],
        onTap: () => _showMore(context),
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

  void _showMore(BuildContext context) {
    showAppSheet(
      context,
      title: '全部功能',
      children: [
        SheetAction(icon: Icons.storage_rounded, label: '存储空间', onTap: () {
          Navigator.pop(context);
          Navigator.of(context).push(appRoute(const StoragePage()));
        }),
        SheetAction(icon: Icons.group_rounded, label: '用户与权限', onTap: () {
          Navigator.pop(context);
          Navigator.of(context).push(appRoute(const UsersPage()));
        }),
        SheetAction(icon: Icons.receipt_long_rounded, label: '系统日志', onTap: () {
          Navigator.pop(context);
          Navigator.of(context).push(appRoute(const LogsPage()));
        }),
        SheetAction(icon: Icons.monitor_heart_rounded, label: '资源监控', onTap: () {
          Navigator.pop(context);
          Navigator.of(context).push(appRoute(const MonitorPage()));
        }),
        SheetAction(icon: Icons.folder_open_rounded, label: '文件浏览', onTap: () {
          Navigator.pop(context);
          onOpenTab(1);
        }),
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

class _ResourceCard extends StatelessWidget {
  final Utilization? utilization;
  final StorageSnapshot? storage;
  final SystemInfo? systemInfo;
  final VoidCallback onOpen;
  const _ResourceCard({required this.utilization, required this.storage, required this.systemInfo, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final util = utilization;
    final memGb = util == null || util.memUsedBytes <= 0 ? '—' : (util.memUsedBytes / 1024 / 1024 / 1024).toStringAsFixed(1);
    final cpu = util?.cpuPercent ?? 0;
    final mem = util?.memPercent ?? 0;
    final storeRatio = storage?.ratio ?? 0;
    final diskTemps = storage?.disks.where((d) => d.temperature > 0).toList() ?? const <DiskInfo>[];
    final avgDiskTemp = diskTemps.isEmpty ? null : diskTemps.map((e) => e.temperature).reduce((a, b) => a + b) / diskTemps.length;
    final cpuTemp = systemInfo?.temperature ?? 0;

    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: '资源监控',
            icon: Icons.monitor_heart_rounded,
            iconColor: const Color(0xFF3D7BFF),
            action: '详情',
            onAction: onOpen,
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              RingGauge(value: cpu / 100, label: 'CPU', size: 92, stroke: 7.5),
              RingGauge(
                value: mem / 100,
                label: '内存',
                size: 92,
                stroke: 7.5,
                valueText: memGb,
                subText: memGb == '—' ? null : 'GB',
                color: const Color(0xFF6C8BFF),
                endColor: const Color(0xFF8FA5FF),
              ),
              RingGauge(
                value: storeRatio,
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
                child: _MiniStat(
                  title: '网络',
                  children: [
                    _MiniStatLine(icon: Icons.arrow_upward_rounded, value: formatSpeed(util?.netTx ?? 0, compact: true)),
                    _MiniStatLine(icon: Icons.arrow_downward_rounded, value: formatSpeed(util?.netRx ?? 0, compact: true)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  title: '硬盘',
                  children: [
                    _MiniStatLine(label: '读', value: formatSpeed(util?.diskRead ?? 0, compact: true)),
                    _MiniStatLine(label: '写', value: formatSpeed(util?.diskWrite ?? 0, compact: true)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  title: '温度',
                  children: [
                    _MiniStatLine(label: 'CPU', value: cpuTemp > 0 ? '${cpuTemp.toStringAsFixed(0)}°C' : '—'),
                    _MiniStatLine(label: '硬盘', value: avgDiskTemp == null ? '—' : '${avgDiskTemp.toStringAsFixed(0)}°C'),
                  ],
                ),
              ),
            ],
          ),
          if (storage == null) ...[
            const SizedBox(height: 12),
            Text('正在读取存储信息…', style: context.texts.labelSmall?.copyWith(color: c.textTertiary)),
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
          SectionHeader(
            title: '存储空间',
            icon: Icons.storage_rounded,
            iconColor: const Color(0xFF28BFA2),
            iconBg: const Color(0xFF28BFA2).withValues(alpha: 0.12),
            action: '管理',
            onAction: onOpen,
          ),
          const SizedBox(height: 14),
          if (volumes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('未读取到存储空间信息', style: context.texts.bodySmall?.copyWith(color: c.textTertiary)),
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
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.dns_rounded, size: 16, color: c.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(volume.name, style: context.texts.titleSmall?.copyWith(fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    '${formatBytes(volume.used)} / ${formatBytes(volume.total)}',
                    style: tabular(context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 11)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (warn ? c.warning : c.success).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                '$percent%',
                style: tabular(context.texts.labelSmall?.copyWith(color: warn ? c.warning : c.success, fontSize: 11)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        SoftProgressBar(
          value: volume.ratio,
          height: 6,
          colors: warn
              ? const [Color(0xFFFFB020), Color(0xFFFF8A3D)]
              : const [Color(0xFF2E6BFF), Color(0xFF63A0FF)],
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
          SectionHeader(
            title: '传输任务',
            icon: Icons.swap_vert_rounded,
            iconColor: const Color(0xFF16C08E),
            iconBg: const Color(0xFF16C08E).withValues(alpha: 0.12),
            action: '全部',
            onAction: onOpen,
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < tasks.length && i < 2; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(tasks[i].title, style: context.texts.titleSmall?.copyWith(fontSize: 13.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(tasks[i].progress * 100).toStringAsFixed(0)}%',
                  style: tabular(context.texts.labelLarge?.copyWith(color: c.primary, fontSize: 12)),
                ),
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
