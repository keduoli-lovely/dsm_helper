import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../downloads/download_tools.dart';
import '../dsm/dsm_client.dart';
import '../dsm/dsm_service.dart';
import '../dsm/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icon_tile.dart';
import '../widgets/feedback.dart';
import '../widgets/file_visual.dart';
import '../widgets/surfaces.dart';
import '../widgets/ui_kit.dart';

class DownloadsPage extends StatefulWidget {
  final bool active;
  const DownloadsPage({super.key, this.active = true});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  List<DownloadTask> _tasks = [];
  bool _loading = true;
  String? _error;
  int _filter = 0;
  Timer? _timer;
  DownloadAdapter? _adapter;
  String? _adapterToolId;
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && widget.active) _load(silent: true);
    });
  }

  @override
  void didUpdateWidget(covariant DownloadsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _load(silent: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _adapter?.dispose();
    super.dispose();
  }

  AppState get _state => context.read<AppState>();

  void _syncAdapter() {
    if (_state.demo) {
      if (_adapter is DemoDownloadAdapter) return;
      _adapter?.dispose();
      _adapter = DemoDownloadAdapter();
      _adapterToolId = 'demo';
      return;
    }
    final tool = _state.activeTool;
    if (tool == null) {
      _adapter?.dispose();
      _adapter = null;
      _adapterToolId = null;
      return;
    }
    if (_adapterToolId == tool.id) return;
    _adapter?.dispose();
    _adapter = null;
    try {
      _adapter = adapterFor(tool, _state.service);
      _adapterToolId = tool.id;
    } on DsmException {
      _adapter = null;
      _adapterToolId = null;
    }
  }

  Future<void> _load({bool silent = false}) async {
    _syncAdapter();
    if (!mounted) return;
    if (_adapter == null) {
      setState(() {
        _loading = false;
        _tasks = [];
        _error = null;
      });
      return;
    }
    if (!silent || !_requested) setState(() => _loading = true);
    _requested = true;
    try {
      final tasks = await _adapter!.list();
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
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

  List<DownloadTask> get _visible {
    switch (_filter) {
      case 1:
        return _tasks.where((t) => t.isActive || t.isPaused).toList();
      case 2:
        return _tasks.where((t) => t.isFinished).toList();
      default:
        return _tasks;
    }
  }

  Future<void> _addTask() async {
    _syncAdapter();
    if (_adapter == null) {
      showToast(context, '请先添加一个下载工具', icon: Icons.info_outline_rounded);
      await _addToolFlow();
      return;
    }
    final controller = TextEditingController();
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null && (data!.text!.startsWith('magnet:') || data.text!.trim().startsWith('http'))) {
        controller.text = data.text!.trim();
      }
    } catch (_) {}

    if (!mounted) return;
    final tool = _state.activeTool;
    await showAppSheet(
      context,
      title: '添加下载任务',
      subtitle: tool == null ? null : '通过 ${tool.label} 下载',
      children: [
        TextField(
          controller: controller,
          maxLines: 3,
          minLines: 2,
          style: context.texts.bodyMedium,
          decoration: const InputDecoration(hintText: '粘贴下载链接或磁力链接'),
        ),
        const SizedBox(height: 10),
        Text('支持 http / https / magnet / ftp 链接', style: context.texts.labelSmall?.copyWith(color: context.colors.textTertiary)),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: () async {
            final uri = controller.text.trim();
            if (uri.isEmpty) return;
            Navigator.pop(context);
            try {
              await _adapter!.add(uri);
              if (mounted) showToast(context, '已添加到下载队列');
              await _load(silent: true);
            } on DsmException catch (e) {
              if (mounted) showToast(context, e.message, icon: Icons.error_outline_rounded);
            }
          },
          child: const Text('添加到下载'),
        ),
      ],
    );
  }

  Future<void> _action(DownloadTask task, String action) async {
    try {
      await _adapter?.action(action, [task.id]);
      if (!mounted) return;
      showToast(context, switch (action) { 'pause' => '已暂停', 'resume' => '继续下载', 'delete' => '任务已删除', _ => '操作完成' });
      await _load(silent: true);
    } on DsmException catch (e) {
      if (mounted) showToast(context, e.message, icon: Icons.error_outline_rounded);
    }
  }

  void _showActions(DownloadTask task) {
    showAppSheet(
      context,
      title: task.title,
      subtitle: '${task.statusLabel} · ${formatBytes(task.downloaded)} / ${formatBytes(task.size)}',
      children: [
        if (task.isActive)
          SheetAction(icon: Icons.pause_rounded, label: '暂停下载', onTap: () {
            Navigator.pop(context);
            _action(task, 'pause');
          }),
        if (task.isPaused)
          SheetAction(icon: Icons.play_arrow_rounded, label: '继续下载', onTap: () {
            Navigator.pop(context);
            _action(task, 'resume');
          }),
        SheetAction(
          icon: Icons.delete_outline_rounded,
          label: '删除任务',
          danger: true,
          onTap: () async {
            Navigator.pop(context);
            final ok = await showConfirm(context, title: '删除这个下载任务？', confirmText: '删除', danger: true);
            if (ok) _action(task, 'delete');
          },
        ),
      ],
    );
  }

  // ---------- 下载工具管理 ----------

  Future<void> _manageTools() async {
    final state = context.read<AppState>();
    await showAppSheet(
      context,
      title: '下载工具',
      subtitle: '下载任务会从选中的工具读取',
      children: [
        for (final tool in state.downloadTools)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SoftCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              radius: 18,
              color: state.activeTool?.id == tool.id ? context.colors.primary.withValues(alpha: 0.07) : null,
              onTap: () async {
                await state.setActiveTool(tool.id);
                if (context.mounted) Navigator.pop(context);
                await _load();
              },
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: context.colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      tool.type == DownloadToolType.aria2 ? Icons.wifi_tethering_rounded : Icons.download_rounded,
                      size: 19,
                      color: context.colors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tool.label, style: context.texts.titleSmall?.copyWith(fontSize: 14)),
                        Text(
                          tool.type == DownloadToolType.dsm ? '${tool.host}:${tool.port}' : '${tool.typeLabel} · ${tool.host}:${tool.port}',
                          style: context.texts.labelSmall?.copyWith(color: context.colors.textTertiary, fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                  if (state.activeTool?.id == tool.id)
                    Icon(Icons.check_circle_rounded, size: 20, color: context.colors.primary),
                  const SizedBox(width: 4),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      Navigator.pop(context);
                      await state.removeDownloadTool(tool.id);
                      if (mounted) await _load();
                    },
                    icon: Icon(Icons.delete_outline_rounded, size: 18, color: context.colors.textTertiary),
                  ),
                ],
              ),
            ),
          ),
        SheetAction(
          icon: Icons.add_rounded,
          label: '添加下载工具',
          subtitle: 'qBittorrent / Aria2',
          onTap: () {
            Navigator.pop(context);
            _addToolFlow();
          },
        ),
        SheetAction(
          icon: Icons.radar_rounded,
          label: '扫描局域网',
          subtitle: '自动发现 qBittorrent / Aria2',
          onTap: () {
            Navigator.pop(context);
            _discoverTools();
          },
        ),
      ],
    );
  }

  Future<void> _discoverTools() async {
    final state = _state;
    final host = state.server?.host ?? '';
    if (host.isEmpty) {
      showToast(context, '请先连接群晖设备', icon: Icons.info_outline_rounded);
      return;
    }
    await showAppSheet(
      context,
      title: '扫描下载工具',
      subtitle: '正在扫描 $host 附近的常用端口',
      children: [
        FutureBuilder<List<DownloadTool>>(
          future: DownloadDiscovery.scan(service: state.service, host: host, trustSelfSigned: state.server?.trustSelfSigned ?? true),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 26),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
              );
            }
            final found = snapshot.data ?? const [];
            if (found.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text('没有自动发现下载工具，可以手动添加。', style: context.texts.bodySmall?.copyWith(color: context.colors.textTertiary)),
              );
            }
            return Column(
              children: [
                for (final tool in found)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SoftCard(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      radius: 16,
                      onTap: () {
                        Navigator.pop(context);
                        _addToolFlow(prefill: tool);
                      },
                      child: Row(
                        children: [
                          Icon(Icons.download_rounded, size: 20, color: context.colors.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('${tool.label} · ${tool.host}:${tool.port}', style: context.texts.titleSmall?.copyWith(fontSize: 13.5)),
                          ),
                          Text('添加', style: context.texts.labelLarge?.copyWith(color: context.colors.primary, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _addToolFlow({DownloadTool? prefill}) async {
    final state = _state;
    final tool = await showModalBottomSheet<DownloadTool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ToolEditor(
        initial: prefill,
        service: state.service,
        defaultHost: state.server?.host ?? '',
        defaultPort: state.server?.port ?? '5000',
        defaultHttps: state.server?.https ?? false,
      ),
    );
    if (tool == null || !mounted) return;
    await state.addDownloadTool(tool);
    await state.setActiveTool(tool.id);
    if (mounted) {
      showToast(context, '已添加 ${tool.label}');
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.colors;
    final tool = state.activeTool;
    final visible = _visible;
    final activeCount = _tasks.where((t) => t.isActive).length;
    final speed = _tasks.where((t) => t.isActive).fold<double>(0, (sum, t) => sum + t.speedDownload);
    final noTools = state.downloadTools.isEmpty;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PageScaffold(
        child: noTools
            ? _buildNoTools(c)
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: Column(
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
                                    Text('下载', style: context.texts.displayMedium),
                                    const SizedBox(height: 4),
                                    Text(
                                      _tasks.isEmpty ? '${tool?.label ?? ''} 任务' : '$activeCount 个进行中 · ${formatSpeed(speed)}',
                                      style: context.texts.bodySmall?.copyWith(color: c.textTertiary, fontSize: 12.5),
                                    ),
                                  ],
                                ),
                              ),
                              CircleIconButton(icon: Icons.tune_rounded, onTap: _manageTools, size: 20),
                              const SizedBox(width: 2),
                              GestureDetector(
                                onTap: _addTask,
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(colors: [Color(0xFF4BE0A8), Color(0xFF16C08E)]),
                                    borderRadius: BorderRadius.circular(15),
                                    boxShadow: [BoxShadow(color: const Color(0xFF16C08E).withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 7))],
                                  ),
                                  child: const Icon(Icons.add_rounded, color: Colors.white, size: 25),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Entrance(
                          index: 1,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final item in state.downloadTools)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: _ToolChip(
                                      tool: item,
                                      selected: state.activeTool?.id == item.id,
                                      onTap: () async {
                                        await state.setActiveTool(item.id);
                                        await _load();
                                      },
                                    ),
                                  ),
                                _ToolChip(
                                  tool: const DownloadTool(id: '__add__', type: DownloadToolType.qbittorrent, name: '添加'),
                                  selected: false,
                                  add: true,
                                  onTap: _addToolFlow,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Entrance(
                          index: 2,
                          child: Row(
                            children: [
                              CategoryChip(label: '全部 ${_tasks.length}', selected: _filter == 0, onTap: () => setState(() => _filter = 0)),
                              const SizedBox(width: 8),
                              CategoryChip(label: '进行中', selected: _filter == 1, onTap: () => setState(() => _filter = 1)),
                              const SizedBox(width: 8),
                              CategoryChip(label: '已完成', selected: _filter == 2, onTap: () => setState(() => _filter = 2)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      color: c.primary,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 132),
                        children: [
                          if (_loading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 60),
                              child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
                            )
                          else if (_error != null)
                            EmptyHint(
                              icon: Icons.cloud_off_rounded,
                              title: '无法读取下载任务',
                              subtitle: _error,
                              action: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  FilledButton(onPressed: _load, style: FilledButton.styleFrom(minimumSize: const Size(100, 42)), child: const Text('重试')),
                                  const SizedBox(width: 10),
                                  OutlinedButton(onPressed: _manageTools, style: OutlinedButton.styleFrom(minimumSize: const Size(100, 42)), child: const Text('检查配置')),
                                ],
                              ),
                            )
                          else if (visible.isEmpty)
                            EmptyHint(
                              icon: Icons.download_done_rounded,
                              title: _filter == 0 ? '还没有下载任务' : '这里还没有任务',
                              subtitle: '点击右上角 + 添加第一个下载',
                              action: FilledButton(
                                onPressed: _addTask,
                                style: FilledButton.styleFrom(minimumSize: const Size(140, 44)),
                                child: const Text('添加下载'),
                              ),
                            )
                          else
                            for (var i = 0; i < visible.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Entrance(
                                  index: 3 + i,
                                  child: _TaskCard(
                                    task: visible[i],
                                    onMore: () => _showActions(visible[i]),
                                    onToggle: () => _action(visible[i], visible[i].isPaused ? 'resume' : 'pause'),
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
  Widget _buildNoTools(AppColors c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 132),
      children: [
        Text('下载', style: context.texts.displayMedium),
        const SizedBox(height: 6),
        Text('连接一个下载工具后即可管理任务', style: context.texts.bodySmall?.copyWith(color: c.textTertiary, fontSize: 12.5)),
        const SizedBox(height: 60),
        Center(
          child: Column(
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF4BE0A8), Color(0xFF16C08E)]),
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [BoxShadow(color: const Color(0xFF16C08E).withValues(alpha: 0.32), blurRadius: 24, offset: const Offset(0, 12))],
                ),
                child: const Icon(Icons.download_rounded, size: 40, color: Colors.white),
              ),
              const SizedBox(height: 18),
              Text('还没有下载工具', style: context.texts.headlineSmall),
              const SizedBox(height: 8),
              Text(
                '支持 qBittorrent（API Key 或账号密码）与 Aria2，\n配置一次就能直接管理下载任务。',
                textAlign: TextAlign.center,
                style: context.texts.bodySmall?.copyWith(color: c.textTertiary, height: 1.7),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 220,
                child: FilledButton.icon(
                  onPressed: _addToolFlow,
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('添加下载工具'),
                ),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _discoverTools,
                icon: const Icon(Icons.radar_rounded, size: 18),
                label: const Text('扫描局域网自动发现'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ToolChip extends StatelessWidget {
  final DownloadTool tool;
  final bool selected;
  final bool add;
  final VoidCallback onTap;
  const _ToolChip({required this.tool, required this.selected, required this.onTap, this.add = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.primary : c.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: selected ? [BoxShadow(color: c.primary.withValues(alpha: 0.26), blurRadius: 12, offset: const Offset(0, 5))] : c.cardShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(add ? Icons.add_rounded : Icons.download_rounded, size: 14, color: selected ? Colors.white : c.textTertiary),
            const SizedBox(width: 5),
            Text(
              tool.label,
              style: context.texts.labelMedium?.copyWith(fontSize: 11.5, color: selected ? Colors.white : c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback onMore;
  final VoidCallback onToggle;
  const _TaskCard({required this.task, required this.onMore, required this.onToggle});

  Color _statusColor(BuildContext context) {
    final c = context.colors;
    if (task.isFinished) return c.success;
    if (task.isPaused) return c.textSecondary;
    if (task.status == 'error') return c.danger;
    if (task.status == 'waiting') return c.warning;
    return c.primary;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final statusColor = _statusColor(context);
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      radius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(task.title, style: context.texts.titleSmall?.copyWith(fontSize: 14.5, height: 1.35), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
                child: Text(task.statusLabel, style: context.texts.labelSmall?.copyWith(color: statusColor, fontSize: 10.5)),
              ),
              GestureDetector(
                onTap: onMore,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
                  child: Icon(Icons.more_horiz_rounded, size: 18, color: c.textTertiary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!task.isFinished) ...[
            SoftProgressBar(value: task.progress, height: 6, colors: task.status == 'error' ? [c.danger, c.danger] : [c.primary, const Color(0xFF63A0FF)]),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('${(task.progress * 100).toStringAsFixed(1)}%', style: tabular(context.texts.labelMedium?.copyWith(color: c.primary, fontSize: 11.5))),
                const Spacer(),
                if (task.isActive) ...[
                  Icon(Icons.arrow_downward_rounded, size: 12, color: c.textTertiary),
                  const SizedBox(width: 2),
                  Text(formatSpeed(task.speedDownload), style: tabular(context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 11))),
                  const SizedBox(width: 10),
                ],
                Text('${formatBytes(task.downloaded)} / ${formatBytes(task.size)}', style: tabular(context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 11))),
              ],
            ),
          ] else
            Row(
              children: [
                Icon(Icons.check_circle_rounded, size: 14, color: c.success),
                const SizedBox(width: 5),
                Text('已完成 · ${formatBytes(task.size)}', style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 11)),
                if (task.destination.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(child: Text(task.destination, style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ],
            ),
          if (task.isActive || task.isPaused) ...[
            const SizedBox(height: 3),
            Row(
              children: [
                if (task.destination.isNotEmpty)
                  Expanded(child: Text(task.destination, style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                const Spacer(),
                _SmallAction(
                  icon: task.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  label: task.isPaused ? '继续' : '暂停',
                  onTap: onToggle,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SmallAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            Icon(icon, size: 14, color: c.primary),
            const SizedBox(width: 3),
            Text(label, style: context.texts.labelSmall?.copyWith(color: c.primary, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _ToolEditor extends StatefulWidget {
  final DownloadTool? initial;
  final DsmService? service;
  final String defaultHost;
  final String defaultPort;
  final bool defaultHttps;
  const _ToolEditor({
    this.initial,
    required this.service,
    required this.defaultHost,
    required this.defaultPort,
    required this.defaultHttps,
  });

  @override
  State<_ToolEditor> createState() => _ToolEditorState();
}

class _ToolEditorState extends State<_ToolEditor> {
  late DownloadToolType _type = widget.initial?.type ?? DownloadToolType.qbittorrent;
  late final TextEditingController _host = TextEditingController(text: widget.initial?.host ?? widget.defaultHost);
  late final TextEditingController _port = TextEditingController(
    text: widget.initial?.port ?? ((widget.initial?.type ?? DownloadToolType.qbittorrent) == DownloadToolType.aria2 ? '6800' : '8080'),
  );
  late final TextEditingController _name = TextEditingController(text: widget.initial?.name ?? '');
  late final TextEditingController _username = TextEditingController(text: widget.initial?.username ?? '');
  late final TextEditingController _password = TextEditingController(text: widget.initial?.password ?? '');
  late final TextEditingController _apiKey = TextEditingController(text: widget.initial?.apiKey ?? '');
  late final TextEditingController _secret = TextEditingController(text: widget.initial?.secret ?? '');
  late bool _https = widget.initial?.https ?? false;
  bool _testing = false;
  String? _error;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _name.dispose();
    _username.dispose();
    _password.dispose();
    _apiKey.dispose();
    _secret.dispose();
    super.dispose();
  }

  DownloadTool _buildTool() {
    final type = _type;
    return DownloadTool(
      id: '${type.name}-${_host.text.trim()}-${_port.text.trim()}-${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      name: _name.text.trim(),
      host: _host.text.trim(),
      port: _port.text.trim().isEmpty ? (type == DownloadToolType.aria2 ? '6800' : '8080') : _port.text.trim(),
      https: _https,
      username: _username.text.trim(),
      password: _password.text,
      apiKey: _apiKey.text.trim(),
      secret: _secret.text.trim(),
    );
  }

  Future<void> _test() async {
    final tool = _buildTool();
    if (tool.host.isEmpty) {
      setState(() => _error = '请填写地址');
      return;
    }
    setState(() {
      _testing = true;
      _error = null;
    });
    try {
      final adapter = adapterFor(tool, widget.service);
      await adapter.testConnection();
      adapter.dispose();
      if (!mounted) return;
      showToast(context, '连接成功');
    } on DsmException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '连接失败，请检查地址、端口以及服务是否已启动');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(color: c.textTertiary.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text('添加下载工具', style: context.texts.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final type in const [DownloadToolType.qbittorrent, DownloadToolType.aria2]) ...[
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _type = type;
                          _port.text = type == DownloadToolType.aria2 ? '6800' : '8080';
                          _https = false;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _type == type ? c.primary.withValues(alpha: 0.12) : c.surfaceAlt,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _type == type ? c.primary.withValues(alpha: 0.4) : Colors.transparent),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          switch (type) {
                            DownloadToolType.qbittorrent => 'qBittorrent',
                            DownloadToolType.aria2 => 'Aria2',
                            _ => 'qBittorrent',
                          },
                          style: context.texts.labelSmall?.copyWith(
                            fontSize: 11,
                            color: _type == type ? c.primary : c.textSecondary,
                            fontWeight: _type == type ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _host,
                    decoration: const InputDecoration(hintText: '地址，例如 192.168.1.10'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _port,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '端口'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _name,
              decoration: const InputDecoration(hintText: '备注名称（可选）'),
            ),
            if (_type == DownloadToolType.qbittorrent) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _apiKey,
                obscureText: true,
                decoration: const InputDecoration(hintText: 'API Key（可选，qBittorrent 5.2+）'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: TextField(controller: _username, decoration: const InputDecoration(hintText: '用户名'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _password, obscureText: true, decoration: const InputDecoration(hintText: '密码'))),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'API Key 与账号密码二选一；使用 Key 时不需要登录。',
                style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5),
              ),
            ],
            if (_type == DownloadToolType.aria2) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _secret,
                obscureText: true,
                decoration: const InputDecoration(hintText: 'RPC Secret（可选，对应 --rpc-secret）'),
              ),
              const SizedBox(height: 4),
              Text(
                'Aria2 需要开启 RPC：--enable-rpc --rpc-listen-all=true --rpc-allow-origin-all',
                style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5, height: 1.4),
              ),
            ],
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('使用 HTTPS', style: context.texts.bodyMedium?.copyWith(color: c.textPrimary, fontSize: 13)),
              value: _https,
              onChanged: (v) => setState(() => _https = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(color: c.danger.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
                child: Text(_error!, style: context.texts.labelSmall?.copyWith(color: c.danger)),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _testing ? null : _test,
                    child: Text(_testing ? '测试中…' : '测试连接'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      final tool = _buildTool();
                      if (tool.host.isEmpty) {
                        setState(() => _error = '请填写地址');
                        return;
                      }
                      Navigator.pop(context, tool);
                    },
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
