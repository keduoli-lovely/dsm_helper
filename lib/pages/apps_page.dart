import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../dsm/dsm_client.dart';
import '../dsm/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/feedback.dart';
import '../widgets/nav_bar.dart';
import '../widgets/surfaces.dart';
import '../widgets/ui_kit.dart';

class AppsPage extends StatefulWidget {
  final bool active;
  const AppsPage({super.key, this.active = true});

  @override
  State<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends State<AppsPage> {
  List<DsmPackage> _packages = [];
  final Set<String> _busy = {};
  bool _loading = true;
  String? _error;
  int _filter = 0;
  String _query = '';
  final _search = TextEditingController();
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant AppsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _load(silent: true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final service = context.read<AppState>().service;
    if (service == null) return;
    if (!silent || !_requested) setState(() => _loading = true);
    _requested = true;
    try {
      final packages = await service.packages();
      if (!mounted) return;
      setState(() {
        _packages = packages;
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

  bool _matches(DsmPackage pkg) {
    if (_filter == 1 && !pkg.isRunning) return false;
    if (_filter == 2 && pkg.isRunning) return false;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      if (!pkg.displayName.toLowerCase().contains(q) && !pkg.id.toLowerCase().contains(q)) return false;
    }
    return true;
  }

  List<DsmPackage> get _visible => _packages.where(_matches).toList();

  List<DsmPackage> get _apps => _visible.where((p) => !p.isSystemService).toList()
    ..sort((a, b) => (b.isRunning ? 1 : 0).compareTo(a.isRunning ? 1 : 0));

  List<DsmPackage> get _system => _visible.where((p) => p.isSystemService && !p.isDocker).toList();

  Future<void> _toggle(DsmPackage pkg, bool running) async {
    if (_busy.contains(pkg.id)) return;
    setState(() => _busy.add(pkg.id));
    try {
      await context.read<AppState>().service!.packageControl(pkg.id, running);
      if (!mounted) return;
      showToast(context, running ? '${pkg.displayName} 已启动' : '${pkg.displayName} 已停止');
      await _load(silent: true);
    } on DsmException catch (e) {
      if (mounted) showToast(context, e.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy.remove(pkg.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = context.watch<AppState>();
    final running = _packages.where((p) => p.isRunning).length;
    final visible = _visible;
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
                          Text('套件中心', style: context.texts.displayMedium),
                          const SizedBox(height: 4),
                          Text(
                            _packages.isEmpty ? '管理已安装的套件' : '$running 个运行中 · 共 ${_packages.length} 个',
                            style: context.texts.bodySmall?.copyWith(color: c.textTertiary, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _load,
                      icon: Icon(Icons.refresh_rounded, color: c.textSecondary, size: 21),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Entrance(
                index: 1,
                child: SearchPill(controller: _search, hint: '搜索套件', onChanged: (v) => setState(() => _query = v.trim())),
              ),
              const SizedBox(height: 12),
              Entrance(
                index: 2,
                child: Row(
                  children: [
                    _FilterPill(label: '全部', selected: _filter == 0, onTap: () => setState(() => _filter = 0)),
                    const SizedBox(width: 8),
                    _FilterPill(label: '运行中', selected: _filter == 1, onTap: () => setState(() => _filter = 1)),
                    const SizedBox(width: 8),
                    _FilterPill(label: '已停止', selected: _filter == 2, onTap: () => setState(() => _filter = 2)),
                  ],
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
                  title: '无法读取套件列表',
                  subtitle: _error,
                  action: FilledButton(onPressed: _load, style: FilledButton.styleFrom(minimumSize: const Size(120, 42)), child: const Text('重试')),
                )
              else if (visible.isEmpty)
                const EmptyHint(icon: Icons.apps_rounded, title: '没有匹配的套件')
              else ...[
                if (_apps.isNotEmpty) ..._section('套件', Icons.apps_rounded, _apps, state),
                if (_system.isNotEmpty) ..._section('系统服务', Icons.shield_rounded, _system, state),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _section(String title, IconData icon, List<DsmPackage> packages, AppState state) {
    final c = context.colors;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
        child: Row(
          children: [
            Icon(icon, size: 16, color: c.textSecondary),
            const SizedBox(width: 6),
            Text(title, style: context.texts.titleSmall?.copyWith(fontSize: 14, color: c.textSecondary)),
            const Spacer(),
            Text('${packages.length}', style: context.texts.labelSmall?.copyWith(color: c.textTertiary)),
          ],
        ),
      ),
      for (final pkg in packages)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _PackageCard(
            package: pkg,
            iconUrls: state.service?.packageIconUrls(pkg.id) ?? const [],
            headers: state.imageHeaders,
            busy: _busy.contains(pkg.id),
            onToggle: (v) => _toggle(pkg, v),
            onTap: () => _showDetail(pkg, state),
          ),
        ),
      const SizedBox(height: 6),
    ];
  }

  void _showDetail(DsmPackage pkg, AppState state) {
    final style = _styleFor(pkg);
    showAppSheet(
      context,
      title: pkg.displayName,
      subtitle: pkg.version.isEmpty ? null : '版本 ${pkg.version}',
      children: [
        Row(
          children: [
            _PackageIcon(
              urls: state.service?.packageIconUrls(pkg.id) ?? const [],
              headers: state.imageHeaders,
              size: 58,
              radius: 18,
              fallbackIcon: style.icon,
              colors: style.colors,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pkg.isSystemService ? '系统服务' : (pkg.isRunning ? '正在运行' : '已停止'),
                    style: context.texts.titleSmall?.copyWith(
                      color: pkg.isSystemService ? context.colors.textSecondary : (pkg.isRunning ? context.colors.success : context.colors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(pkg.id, style: context.texts.labelSmall?.copyWith(color: context.colors.textTertiary)),
                  if (pkg.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(pkg.description, style: context.texts.bodySmall?.copyWith(color: context.colors.textTertiary), maxLines: 3, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (pkg.canStart)
          FilledButton.icon(
            onPressed: _busy.contains(pkg.id)
                ? null
                : () {
                    Navigator.pop(context);
                    _toggle(pkg, !pkg.isRunning);
                  },
            icon: Icon(pkg.isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 20),
            label: Text(pkg.isRunning ? '停止套件' : '启动套件'),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: context.colors.surfaceAlt, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 18, color: context.colors.textTertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '系统服务由 DSM 管理，不能在这里停止',
                    style: context.texts.bodySmall?.copyWith(color: context.colors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterPill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? c.primary : c.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: selected ? [BoxShadow(color: c.primary.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 5))] : c.cardShadow,
        ),
        child: Text(
          label,
          style: context.texts.labelMedium?.copyWith(fontSize: 12, color: selected ? Colors.white : c.textSecondary),
        ),
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  final DsmPackage package;
  final List<String> iconUrls;
  final Map<String, String> headers;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;
  const _PackageCard({
    required this.package,
    required this.iconUrls,
    required this.headers,
    required this.busy,
    required this.onToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = _styleFor(package);
    final statusColor = package.statusKnown ? (package.isRunning ? c.success : c.textTertiary) : c.textTertiary;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      radius: 22,
      onTap: onTap,
      child: Row(
        children: [
          _PackageIcon(
            urls: iconUrls,
            headers: headers,
            size: 48,
            radius: 15,
            fallbackIcon: style.icon,
            colors: style.colors,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(package.displayName, style: context.texts.titleSmall?.copyWith(fontSize: 14.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor)),
                    const SizedBox(width: 5),
                    Text(
                      package.isSystemService ? '系统服务 · ${package.isRunning ? '运行中' : '已停止'}' : (package.isRunning ? '运行中' : '已停止'),
                      style: context.texts.labelSmall?.copyWith(color: package.isSystemService ? c.textTertiary : statusColor, fontSize: 11),
                    ),
                    if (package.version.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text('v${package.version.split('-').first}', style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(width: 28, height: 28, child: Padding(padding: EdgeInsets.all(5), child: CircularProgressIndicator(strokeWidth: 2))),
          if (!busy && package.canStart)
            Switch(value: package.isRunning, onChanged: onToggle),
          if (!busy && !package.canStart)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Icon(Icons.lock_outline_rounded, size: 18, color: c.textTertiary),
            ),
        ],
      ),
    );
  }
}

class _PackageIcon extends StatefulWidget {
  final List<String> urls;
  final Map<String, String> headers;
  final double size;
  final double radius;
  final IconData fallbackIcon;
  final List<Color> colors;
  const _PackageIcon({
    required this.urls,
    required this.headers,
    required this.size,
    required this.radius,
    required this.fallbackIcon,
    required this.colors,
  });

  @override
  State<_PackageIcon> createState() => _PackageIconState();
}

class _PackageIconState extends State<_PackageIcon> {
  int _index = 0;

  Widget _fallback() {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: widget.colors),
        borderRadius: BorderRadius.circular(widget.radius),
        boxShadow: [BoxShadow(color: widget.colors.last.withValues(alpha: 0.28), blurRadius: 13, offset: const Offset(0, 6))],
      ),
      child: Icon(widget.fallbackIcon, color: Colors.white, size: widget.size * 0.48),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) return _fallback();
    final index = _index.clamp(0, widget.urls.length - 1);
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Image.network(
        widget.urls[index],
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        headers: widget.headers,
        errorBuilder: (_, __, ___) {
          if (index < widget.urls.length - 1) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _index = index + 1);
            });
          }
          return _fallback();
        },
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _fallback();
        },
      ),
    );
  }
}

class _PackageStyle {
  final IconData icon;
  final List<Color> colors;
  const _PackageStyle(this.icon, this.colors);
}

_PackageStyle _styleFor(DsmPackage pkg) {
  final id = pkg.id.toLowerCase();
  if (id.contains('photo')) return const _PackageStyle(Icons.photo_library_rounded, [Color(0xFFB79BFF), Color(0xFF8A6BFF)]);
  if (id.contains('download')) return const _PackageStyle(Icons.download_rounded, [Color(0xFF4BE0A8), Color(0xFF16C08E)]);
  if (id.contains('docker') || id.contains('container')) return const _PackageStyle(Icons.widgets_rounded, [Color(0xFF4FA8FF), Color(0xFF2E7BFF)]);
  if (id.contains('drive')) return const _PackageStyle(Icons.cloud_rounded, [Color(0xFF66C4FF), Color(0xFF3090FF)]);
  if (id.contains('plex')) return const _PackageStyle(Icons.play_circle_fill_rounded, [Color(0xFFE5A100), Color(0xFFC98A00)]);
  if (id.contains('virtual') || id.contains('vmm')) return const _PackageStyle(Icons.desktop_windows_rounded, [Color(0xFF9AA6BD), Color(0xFF6E7A91)]);
  if (id.contains('maria') || id.contains('mysql')) return const _PackageStyle(Icons.storage_rounded, [Color(0xFF5BD8A5), Color(0xFF1FB980)]);
  if (id.contains('web')) return const _PackageStyle(Icons.public_rounded, [Color(0xFF6FA9FF), Color(0xFF3D78F0)]);
  if (id.contains('log')) return const _PackageStyle(Icons.receipt_long_rounded, [Color(0xFFFFD36E), Color(0xFFFFB020)]);
  if (id.contains('note')) return const _PackageStyle(Icons.sticky_note_2_rounded, [Color(0xFFFFB86B), Color(0xFFFF8F2E)]);
  if (id.contains('backup')) return const _PackageStyle(Icons.backup_rounded, [Color(0xFF8FD3FF), Color(0xFF4AA8F0)]);
  if (id.contains('security') || id.contains('antivirus')) return const _PackageStyle(Icons.security_rounded, [Color(0xFF6FE0C8), Color(0xFF23B99C)]);
  if (id.contains('chat') || id.contains('message')) return const _PackageStyle(Icons.forum_rounded, [Color(0xFFFF9FB6), Color(0xFFFF6E93)]);
  if (pkg.isSystemService) return const _PackageStyle(Icons.shield_rounded, [Color(0xFFA7B4CC), Color(0xFF7B88A1)]);
  return const _PackageStyle(Icons.extension_rounded, [Color(0xFFA7B4CC), Color(0xFF7B88A1)]);
}
