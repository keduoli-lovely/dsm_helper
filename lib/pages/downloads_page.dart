import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../dsm/dsm_client.dart';
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
  int _filter = 0; // 0 全部 1 进行中 2 已完成
  Timer? _timer;
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
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final service = context.read<AppState>().service;
    if (service == null) return;
    if (!silent || !_requested) setState(() => _loading = true);
    _requested = true;
    try {
      final tasks = await service.downloads();
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
    final controller = TextEditingController();
    String? pasted;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null && (data!.text!.startsWith('magnet:') || data.text!.startsWith('http'))) {
        pasted = data.text;
        controller.text = pasted!;
      }
    } catch (_) {}

    if (!mounted) return;
    await showAppSheet(
      context,
      title: '添加下载任务',
      subtitle: '支持 http / https / magnet / ftp 链接',
      children: [
        TextField(
          controller: controller,
          maxLines: 3,
          minLines: 2,
          style: context.texts.bodyMedium,
          decoration: const InputDecoration(hintText: '粘贴下载链接或磁力链接'),
        ),
        const SizedBox(height: 10),
        Text('任务会保存到 Download Station 的默认目录', style: context.texts.labelSmall?.copyWith(color: context.colors.textTertiary)),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: () async {
            final uri = controller.text.trim();
            if (uri.isEmpty) return;
            Navigator.pop(context);
            try {
              await context.read<AppState>().service!.addDownload(uri);
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
      await context.read<AppState>().service!.downloadAction(action, [task.id]);
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final visible = _visible;
    final activeCount = _tasks.where((t) => t.isActive).length;
    final speed = _tasks.where((t) => t.isActive).fold<double>(0, (sum, t) => sum + t.speedDownload);
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
                          Text('下载', style: context.texts.displayMedium),
                          const SizedBox(height: 4),
                          Text(
                            _tasks.isEmpty ? 'Download Station 任务' : '$activeCount 个进行中 · ${formatSpeed(speed)}',
                            style: context.texts.bodySmall?.copyWith(color: c.textTertiary, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
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
              const SizedBox(height: 18),
              Entrance(
                index: 1,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
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
              ),
              const SizedBox(height: 16),
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
                  action: FilledButton(
                    onPressed: _load,
                    style: FilledButton.styleFrom(minimumSize: const Size(120, 42)),
                    child: const Text('重试'),
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
                    child: Entrance(index: 2 + i, child: _TaskCard(task: visible[i], onMore: () => _showActions(visible[i]), onToggle: () => _action(visible[i], visible[i].isPaused ? 'resume' : 'pause'))),
                  ),
            ],
          ),
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
