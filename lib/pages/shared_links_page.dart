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
import '../widgets/surfaces.dart';
import '../widgets/ui_kit.dart';

class SharedLinksPage extends StatefulWidget {
  const SharedLinksPage({super.key});

  @override
  State<SharedLinksPage> createState() => _SharedLinksPageState();
}

class _SharedLinksPageState extends State<SharedLinksPage> {
  List<SharedLink> _links = [];
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
      final links = await service.sharingLinks();
      if (!mounted) return;
      setState(() {
        _links = links;
        _loading = false;
        _error = null;
      });
    } on DsmException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _copy(SharedLink link) async {
    await Clipboard.setData(ClipboardData(text: link.url));
    if (mounted) showToast(context, '链接已复制');
  }

  Future<void> _delete(SharedLink link) async {
    final ok = await showConfirm(context, title: '删除这条共享链接？', message: '已分享出去的链接将立即失效。', confirmText: '删除', danger: true);
    if (!ok) return;
    try {
      await context.read<AppState>().service!.deleteSharingLinks([link.id]);
      if (mounted) showToast(context, '已删除共享链接');
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
              title: '共享链接',
              subtitle: _links.isEmpty ? '管理 File Station 分享出去的文件' : '共 ${_links.length} 条链接',
              actions: [CircleIconButton(icon: Icons.refresh_rounded, onTap: _load, size: 20)],
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
                  : _error != null
                      ? Center(child: EmptyHint(icon: Icons.cloud_off_rounded, title: '无法读取共享链接', subtitle: _error, action: FilledButton(onPressed: _load, child: const Text('重试'))))
                      : _links.isEmpty
                          ? const Center(child: EmptyHint(icon: Icons.link_off_rounded, title: '还没有共享链接', subtitle: '在文件详情中点击「创建共享链接」即可生成'))
                          : RefreshIndicator(
                              onRefresh: _load,
                              color: c.primary,
                              child: ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                                itemCount: _links.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final link = _links[index];
                                  return SoftCard(
                                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                                    radius: 20,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              width: 34,
                                              height: 34,
                                              decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(11)),
                                              child: Icon(Icons.link_rounded, size: 18, color: c.primary),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                link.url,
                                                style: context.texts.bodySmall?.copyWith(color: c.textSecondary, fontSize: 12),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (link.expireDate.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text('有效期：${link.expireDate}', style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5)),
                                        ],
                                        const SizedBox(height: 10),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            _LinkAction(icon: Icons.copy_rounded, label: '复制', onTap: () => _copy(link)),
                                            const SizedBox(width: 8),
                                            _LinkAction(icon: Icons.open_in_new_rounded, label: '打开', onTap: () => launchUrl(Uri.parse(link.url), mode: LaunchMode.externalApplication)),
                                            const SizedBox(width: 8),
                                            _LinkAction(icon: Icons.delete_outline_rounded, label: '删除', danger: true, onTap: () => _delete(link)),
                                          ],
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

class _LinkAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  const _LinkAction({required this.icon, required this.label, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = danger ? c.danger : c.primary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: context.texts.labelSmall?.copyWith(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
