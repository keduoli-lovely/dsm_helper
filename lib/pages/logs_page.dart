import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../dsm/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icon_tile.dart';
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PageScaffold(
        child: Column(
          children: [
            DetailHeader(
              title: '系统日志',
              subtitle: _logs.isEmpty ? '最近的系统与登录记录' : '最近 ${_logs.length} 条记录',
              actions: [CircleIconButton(icon: Icons.refresh_rounded, onTap: _load, size: 20)],
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
                  : _error != null
                      ? Center(child: EmptyHint(icon: Icons.cloud_off_rounded, title: '读取日志失败', subtitle: _error, action: FilledButton(onPressed: _load, child: const Text('重试'))))
                      : _logs.isEmpty
                          ? const Center(child: EmptyHint(icon: Icons.receipt_long_rounded, title: '暂无日志'))
                          : ListView.separated(
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                              itemCount: _logs.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final log = _logs[index];
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
          ],
        ),
      ),
    );
  }
}
