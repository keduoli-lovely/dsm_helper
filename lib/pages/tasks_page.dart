import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../dsm/dsm_client.dart';
import '../dsm/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/feedback.dart';
import '../widgets/app_icon_tile.dart';
import '../widgets/surfaces.dart';
import '../widgets/ui_kit.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  List<ScheduledTask> _tasks = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final service = context.read<AppState>().service;
    if (service == null) return;
    setState(() => _loading = true);
    try {
      final tasks = await service.tasks();
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _toggle(ScheduledTask task, bool enabled) async {
    try {
      await context.read<AppState>().service!.toggleTask(task.id, enabled);
      if (!mounted) return;
      showToast(context, enabled ? '已启用「${task.name}」' : '已停用「${task.name}」');
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
              title: '计划任务',
              subtitle: _tasks.isEmpty ? null : '共 ${_tasks.length} 个任务',
              actions: [CircleIconButton(icon: Icons.refresh_rounded, onTap: _load, size: 20)],
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
                  : _error != null
                      ? Center(child: EmptyHint(icon: Icons.cloud_off_rounded, title: '读取任务失败', subtitle: _error, action: FilledButton(onPressed: _load, child: const Text('重试'))))
                      : _tasks.isEmpty
                          ? const Center(child: EmptyHint(icon: Icons.schedule_rounded, title: '还没有计划任务', subtitle: '可在 DSM 控制面板中创建'))
                          : ListView.separated(
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                              itemCount: _tasks.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final task = _tasks[index];
                                return SoftCard(
                                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                                  radius: 20,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: c.primary.withValues(alpha: 0.10),
                                          borderRadius: BorderRadius.circular(13),
                                        ),
                                        child: Icon(Icons.schedule_rounded, size: 19, color: c.primary),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(task.name, style: context.texts.titleSmall?.copyWith(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                                            const SizedBox(height: 3),
                                            Text(
                                              task.nextRun.isEmpty ? '未设置下次运行时间' : '下次运行 ${task.nextRun}',
                                              style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Switch(value: task.enabled, onChanged: (v) => _toggle(task, v)),
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
