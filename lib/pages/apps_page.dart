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
  bool _library = false;
  List<CatalogPackage> _catalog = [];
  List<PackageVolume> _volumes = [];
  bool _catalogLoading = false;
  String? _catalogError;

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

  Future<void> _loadCatalog() async {
    final service = context.read<AppState>().service;
    if (service == null) return;
    setState(() {
      _catalogLoading = true;
      _catalogError = null;
    });
    try {
      final results = await Future.wait([
        service.catalogPackages(),
        service.packageVolumes(),
      ]);
      if (!mounted) return;
      setState(() {
        _catalog = results[0] as List<CatalogPackage>;
        _volumes = results[1] as List<PackageVolume>;
        _catalogLoading = false;
      });
    } on DsmException catch (e) {
      if (!mounted) return;
      setState(() {
        _catalogError = e.message;
        _catalogLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _catalogError = '';
        _catalogLoading = false;
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
                    _FilterPill(label: '已安装', selected: !_library, onTap: () => setState(() => _library = false)),
                    const SizedBox(width: 8),
                    _FilterPill(
                      label: '套件库',
                      selected: _library,
                      onTap: () {
                        setState(() => _library = true);
                        if (_catalog.isEmpty && !_catalogLoading) _loadCatalog();
                      },
                    ),
                    const Spacer(),
                    if (_library)
                      Text('${_catalog.length} 个套件', style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5)),
                  ],
                ),
              ),
              if (!_library) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    _FilterPill(label: '全部', selected: _filter == 0, onTap: () => setState(() => _filter = 0)),
                    const SizedBox(width: 8),
                    _FilterPill(label: '运行中', selected: _filter == 1, onTap: () => setState(() => _filter = 1)),
                    const SizedBox(width: 8),
                    _FilterPill(label: '已停止', selected: _filter == 2, onTap: () => setState(() => _filter = 2)),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              if (_library) ...[
                if (_catalogLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
                  )
                else if (_catalogError != null)
                  EmptyHint(
                    icon: Icons.cloud_off_rounded,
                    title: '无法读取套件库',
                    subtitle: _catalogError,
                    action: FilledButton(onPressed: _loadCatalog, style: FilledButton.styleFrom(minimumSize: const Size(120, 42)), child: const Text('重试')),
                  )
                else if (_catalog.isEmpty)
                  const EmptyHint(icon: Icons.storefront_rounded, title: '套件库为空', subtitle: '当前账号可能没有套件中心权限')
                else
                  ..._catalogWidgets(state),
              ] else if (_loading)
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

  bool _versionGreater(String latest, String installed) {
    List<int> parse(String value) => RegExp(r'\d+').allMatches(value).map((m) => int.tryParse(m.group(0)!) ?? 0).toList();
    final a = parse(latest);
    final b = parse(installed);
    for (var i = 0; i < a.length || i < b.length; i++) {
      final left = i < a.length ? a[i] : 0;
      final right = i < b.length ? b[i] : 0;
      if (left != right) return left > right;
    }
    return false;
  }

  List<Widget> _catalogWidgets(AppState state) {
    final installed = {for (final p in _packages) p.id.toLowerCase(): p};
    final items = _catalog.where((item) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return item.name.toLowerCase().contains(q) || item.id.toLowerCase().contains(q);
    }).toList();
    bool canUpdate(CatalogPackage item) {
      final pkg = installed[item.id.toLowerCase()];
      return pkg != null && item.version.isNotEmpty && _versionGreater(item.version, pkg.version);
    }

    items.sort((a, b) {
      final au = canUpdate(a) ? 0 : (installed.containsKey(a.id.toLowerCase()) ? 2 : 1);
      final bu = canUpdate(b) ? 0 : (installed.containsKey(b.id.toLowerCase()) ? 2 : 1);
      if (au != bu) return au.compareTo(bu);
      return a.name.compareTo(b.name);
    });

    return [
      for (final item in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _catalogCard(item, installed[item.id.toLowerCase()], canUpdate(item), state),
        ),
      const SizedBox(height: 6),
    ];
  }

  Widget _catalogCard(CatalogPackage item, DsmPackage? installed, bool canUpdate, AppState state) {
    final c = context.colors;
    final style = _styleFor(DsmPackage(id: item.id, name: item.name, version: item.version, status: ''));
    final label = canUpdate ? '更新' : (installed != null ? '已安装' : '安装');
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      radius: 18,
      onTap: () => _showCatalogDetail(item, installed, canUpdate, state),
      child: Row(
        children: [
          _PackageIcon(
            urls: state.service?.packageIconUrls(item.id) ?? const [],
            headers: state.imageHeaders,
            size: 46,
            radius: 14,
            fallbackIcon: style.icon,
            colors: style.colors,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: context.texts.titleSmall?.copyWith(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(item.description.isEmpty ? item.id : item.description, style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text(
                  installed == null ? 'v${item.version}' : '已安装 ${installed.version}${canUpdate ? ' → ${item.version}' : ''}',
                  style: context.texts.labelSmall?.copyWith(color: canUpdate ? c.primary : c.textTertiary, fontSize: 10.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (label == '已安装')
            Text('已安装', style: context.texts.labelSmall?.copyWith(color: c.success, fontSize: 11))
          else
            FilledButton(
              onPressed: () => _install(item, canUpdate),
              style: FilledButton.styleFrom(minimumSize: const Size(64, 34), padding: const EdgeInsets.symmetric(horizontal: 14)),
              child: Text(label),
            ),
        ],
      ),
    );
  }

  void _showCatalogDetail(CatalogPackage item, DsmPackage? installed, bool canUpdate, AppState state) {
    final style = _styleFor(DsmPackage(id: item.id, name: item.name, version: item.version, status: ''));
    showAppSheet(
      context,
      title: item.name,
      subtitle: installed == null ? '版本 ${item.version}' : '已安装 ${installed.version}${canUpdate ? ' · 可更新到 ${item.version}' : ''}',
      children: [
        Row(
          children: [
            _PackageIcon(
              urls: state.service?.packageIconUrls(item.id) ?? const [],
              headers: state.imageHeaders,
              size: 58,
              radius: 18,
              fallbackIcon: style.icon,
              colors: style.colors,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(item.description.isEmpty ? '暂无描述' : item.description, style: context.texts.bodySmall?.copyWith(color: context.colors.textTertiary, height: 1.5)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (canUpdate)
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _install(item, true);
            },
            child: Text('更新到 ${item.version}'),
          )
        else if (installed == null)
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _install(item, false);
            },
            child: const Text('安装套件'),
          )
        else
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _uninstall(installed);
            },
            style: FilledButton.styleFrom(backgroundColor: context.colors.danger),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('卸载套件'),
          ),
      ],
    );
  }

  Future<PackageVolume?> _pickVolume() async {
    if (_volumes.isEmpty) return null;
    if (_volumes.length == 1) return _volumes.first;
    return showDialog<PackageVolume>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('安装到哪个存储空间'),
        children: [
          for (final volume in _volumes)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, volume),
              child: Text('${volume.name}${volume.freeBytes > 0 ? ' · 可用 ${formatBytes(volume.freeBytes)}' : ''}'),
            ),
        ],
      ),
    );
  }

  Future<void> _install(CatalogPackage item, bool update) async {
    final service = context.read<AppState>().service;
    if (service == null) return;
    if (_volumes.isEmpty) {
      try {
        _volumes = await service.packageVolumes();
      } on DsmException catch (e) {
        if (mounted) showToast(context, e.message, icon: Icons.error_outline_rounded);
        return;
      }
    }
    final volume = await _pickVolume();
    if (volume == null) {
      if (mounted) showToast(context, '没有可用的存储空间', icon: Icons.info_outline_rounded);
      return;
    }
    if (!mounted) return;
    final ok = await showConfirm(
      context,
      title: update ? '更新 ${item.name}？' : '安装 ${item.name}？',
      message: '安装位置：${volume.name}。安装期间请保持设备在线。',
      confirmText: update ? '更新' : '安装',
    );
    if (!ok || !mounted) return;

    var progress = 0.0;
    var status = '准备安装…';
    StateSetter? setDialog;
    var dialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          setDialog = setDialogState;
          return AlertDialog(
            title: Text(update ? '正在更新' : '正在安装'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: progress > 0 ? (progress / 100).clamp(0, 1) : null),
                const SizedBox(height: 12),
                Text(status, style: context.texts.bodySmall?.copyWith(color: context.colors.textTertiary)),
              ],
            ),
          );
        },
      ),
    );
    try {
      final taskId = await service.installPackage(item.id, volume.path, beta: item.beta);
      while (true) {
        await Future.delayed(const Duration(seconds: 2));
        final data = await service.packageInstallStatus(taskId);
        final value = data['progress'];
        progress = value is num ? value.toDouble() : double.tryParse('${value ?? ''}') ?? progress;
        status = '${data['status'] ?? ''}'.isEmpty ? '安装中…' : '${data['status']}';
        if (!mounted) return;
        setDialog?.call(() {});
        if (data['finished'] == true) break;
      }
      if (!mounted) return;
      if (dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogOpen = false;
      }
      showToast(context, update ? '${item.name} 已更新' : '${item.name} 已安装');
      await _load(silent: true);
      await _loadCatalog();
    } on DsmException catch (e) {
      if (!mounted) return;
      if (dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogOpen = false;
      }
      showToast(context, e.message, icon: Icons.error_outline_rounded);
    }
  }
  Future<void> _uninstall(DsmPackage pkg) async {
    final service = context.read<AppState>().service;
    if (service == null) return;
    final ok = await showConfirm(
      context,
      title: '卸载 ${pkg.displayName}？',
      message: '套件数据可能一并删除，请确认已在 DSM 中备份。',
      confirmText: '卸载',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await service.uninstallPackage(pkg.id);
      if (!mounted) return;
      showToast(context, '${pkg.displayName} 已卸载');
      await _load(silent: true);
      if (_library) await _loadCatalog();
    } on DsmException catch (e) {
      if (mounted) showToast(context, e.message, icon: Icons.error_outline_rounded);
    }
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
        if (!pkg.isSystemService) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _uninstall(pkg);
            },
            style: OutlinedButton.styleFrom(foregroundColor: context.colors.danger),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('卸载套件'),
          ),
        ],      ],
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
