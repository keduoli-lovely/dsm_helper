import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../dsm/dsm_client.dart';
import '../dsm/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icon_tile.dart';
import '../widgets/feedback.dart';
import '../widgets/nav_bar.dart';
import '../widgets/surfaces.dart';
import '../widgets/ui_kit.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  List<LogEntry> _logs = [];
  bool _loading = true;
  String? _error;
  int _filter = 0;
  String _query = '';
  final _search = TextEditingController();

  static const _filters = ['全部', '登录', '文件', '系统', '错误'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final service = context.read<AppState>().service;
    if (service == null) return;
    setState(() => _loading = true);
    try {
      final logs = await service.logs();
      if (!mounted) return;
      setState(() {
        _logs = logs;
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

  bool _matchFilter(LogEntry log) {
    final text = '${log.what} ${log.who} ${log.from}'.toLowerCase();
    switch (_filter) {
      case 1:
        return text.contains('登录') || text.contains('login') || text.contains('auth') || text.contains('登入');
      case 2:
        return text.contains('文件') || text.contains('file') || text.contains('上传') || text.contains('下载') || text.contains('smb') || text.contains('ftp') || text.contains('webdav');
      case 3:
        return text.contains('系统') || text.contains('system') || text.contains('套件') || text.contains('package') || text.contains('存储') || text.contains('smart') || text.contains('更新');
      case 4:
        return text.contains('错误') || text.contains('失败') || text.contains('error') || text.contains('fail') || text.contains('警告') || text.contains('warning');
      default:
        return true;
    }
  }

  List<LogEntry> get _visible {
    final q = _query.trim().toLowerCase();
    return _logs.where((log) {
      if (!_matchFilter(log)) return false;
      if (q.isEmpty) return true;
      return '${log.what} ${log.who} ${log.from} ${log.time}'.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _clearLogs() async {
    final state = context.read<AppState>();
    if (state.demo) {
      showToast(context, '演示模式不会清除真实日志', icon: Icons.info_outline_rounded);
      return;
    }
    final ok = await showConfirm(
      context,
      title: '清除系统日志？',
      message: '将删除 DSM 本机记录的日志，操作不可恢复。',
      confirmText: '清除',
      danger: true,
    );
    if (!ok) return;
    try {
      await state.service!.clearLogs();
      if (mounted) showToast(context, '日志已清除');
      await _load();
    } on DsmException catch (e) {
      if (mounted) showToast(context, e.message, icon: Icons.error_outline_rounded);
    }
  }

  IconData _iconFor(LogEntry log) {
    final text = '${log.what}${log.who}'.toLowerCase();
    if (text.contains('登录') || text.contains('login')) return Icons.login_rounded;
    if (text.contains('smart') || text.contains('硬盘') || text.contains('存储')) return Icons.storage_rounded;
    if (text.contains('下载') || text.contains('download')) return Icons.download_rounded;
    if (text.contains('套件') || text.contains('package')) return Icons.extension_rounded;
    if (text.contains('备份') || text.contains('backup')) return Icons.backup_rounded;
    return Icons.receipt_long_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final visible = _visible;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PageScaffold(
        child: Column(
          children: [
            DetailHeader(
              title: '系统日志',
              subtitle: _logs.isEmpty ? '最近的系统与登录记录' : '${visible.length} / ${_logs.length} 条记录',
              actions: [
                CircleIconButton(icon: Icons.delete_sweep_outlined, onTap: _clearLogs, size: 21),
                const SizedBox(width: 2),
                CircleIconButton(icon: Icons.refresh_rounded, onTap: _load, size: 20),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SearchPill(
                controller: _search,
                hint: '搜索日志内容',
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  for (var i = 0; i < _filters.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() => _filter = i),
                      behavior: HitTestBehavior.opaque,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                        decoration: BoxDecoration(
                          color: _filter == i ? c.primary : c.surface,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: _filter == i ? [BoxShadow(color: c.primary.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4))] : c.cardShadow,
                        ),
                        child: Text(
                          _filters[i],
                          style: context.texts.labelMedium?.copyWith(fontSize: 12, color: _filter == i ? Colors.white : c.textSecondary),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
                  : _error != null
                      ? Center(child: EmptyHint(icon: Icons.cloud_off_rounded, title: '读取日志失败', subtitle: _error, action: FilledButton(onPressed: _load, child: const Text('重试'))))
                      : visible.isEmpty
                          ? const Center(child: EmptyHint(icon: Icons.receipt_long_rounded, title: '没有匹配的日志', subtitle: '试试切换筛选条件或清空搜索'))
                          : RefreshIndicator(
                              onRefresh: _load,
                              color: c.primary,
                              child: ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
                                itemCount: visible.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final log = visible[index];
                                  return SoftCard(
                                    padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                                    radius: 20,
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 38,
                                          height: 38,
                                          decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
                                          child: Icon(_iconFor(log), size: 18, color: c.primary),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                log.what.isEmpty ? '系统事件' : log.what,
                                                style: context.texts.bodyMedium?.copyWith(color: c.textPrimary, fontSize: 13.5, height: 1.5),
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  if (log.who.isNotEmpty)
                                                    Text(log.who, style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5)),
                                                  if (log.who.isNotEmpty && log.time.isNotEmpty)
                                                    Text(' · ', style: context.texts.labelSmall?.copyWith(color: c.textTertiary)),
                                                  if (log.time.isNotEmpty)
                                                    Text(log.time, style: tabular(context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5))),
                                                  if (log.from.isNotEmpty)
                                                    Expanded(
                                                      child: Text(
                                                        ' · ${log.from}',
                                                        style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
