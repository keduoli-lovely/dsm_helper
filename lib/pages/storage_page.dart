import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../dsm/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icon_tile.dart';
import '../widgets/surfaces.dart';
import '../widgets/ui_kit.dart';

class StoragePage extends StatefulWidget {
  const StoragePage({super.key});

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  StorageSnapshot? _storage;
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
      final storage = await service.storage();
      if (!mounted) return;
      setState(() {
        _storage = storage;
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final storage = _storage;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PageScaffold(
        child: Column(
          children: [
            DetailHeader(
              title: '存储空间',
              subtitle: storage == null ? null : '总容量 ${formatBytes(storage.totalBytes)}',
              actions: [CircleIconButton(icon: Icons.refresh_rounded, onTap: _load, size: 20)],
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
                  : _error != null
                      ? Center(child: EmptyHint(icon: Icons.cloud_off_rounded, title: '读取存储信息失败', subtitle: _error, action: FilledButton(onPressed: _load, child: const Text('重试'))))
                      : ListView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                          children: [
                            if (storage != null)
                              SoftCard(
                                padding: const EdgeInsets.all(20),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 108,
                                      height: 108,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          SizedBox(
                                            width: 108,
                                            height: 108,
                                            child: CircularProgressIndicator(
                                              value: storage.ratio,
                                              strokeWidth: 10,
                                              strokeCap: StrokeCap.round,
                                              backgroundColor: c.surfaceAlt,
                                              valueColor: AlwaysStoppedAnimation(c.primary),
                                            ),
                                          ),
                                          Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text('${(storage.ratio * 100).toStringAsFixed(0)}%', style: tabular(context.texts.headlineSmall)),
                                              Text('已使用', style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5)),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 18),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('总容量', style: context.texts.labelMedium?.copyWith(color: c.textTertiary)),
                                          const SizedBox(height: 3),
                                          Text(formatBytes(storage.totalBytes), style: tabular(context.texts.headlineMedium)),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              _Dot(color: c.primary, label: '已用 ${formatBytes(storage.usedBytes)}'),
                                            ],
                                          ),
                                          const SizedBox(height: 5),
                                          Row(
                                            children: [
                                              _Dot(color: c.textTertiary, label: '可用 ${formatBytes(storage.totalBytes - storage.usedBytes)}'),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 18),
                            Text('存储空间', style: context.texts.titleMedium),
                            const SizedBox(height: 10),
                            for (final volume in storage?.volumes ?? const <VolumeInfo>[])
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _VolumeCard(volume: volume),
                              ),
                            if ((storage?.volumes ?? []).isEmpty)
                              const EmptyHint(icon: Icons.storage_rounded, title: '没有存储空间信息'),
                            if ((storage?.disks ?? []).isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text('硬盘', style: context.texts.titleMedium),
                              const SizedBox(height: 10),
                              SoftCard(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                                child: Column(
                                  children: [
                                    for (var i = 0; i < storage!.disks.length; i++) ...[
                                      if (i > 0) Divider(height: 1, color: c.border.withValues(alpha: 0.6)),
                                      _DiskRow(disk: storage.disks[i]),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  final String label;
  const _Dot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: context.texts.labelSmall?.copyWith(color: context.colors.textSecondary, fontSize: 11)),
      ],
    );
  }
}

class _VolumeCard extends StatelessWidget {
  final VolumeInfo volume;
  const _VolumeCard({required this.volume});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final warn = volume.ratio > 0.85;
    return SoftCard(
      padding: const EdgeInsets.all(16),
      radius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (warn ? c.warning : c.primary).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(Icons.dns_rounded, size: 20, color: warn ? c.warning : c.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(volume.name, style: context.texts.titleSmall?.copyWith(fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(
                      [volume.fsLabel, volume.raidLabel].where((e) => e.isNotEmpty).join(' · '),
                      style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              Text('${(volume.ratio * 100).toStringAsFixed(0)}%', style: tabular(context.texts.titleLarge?.copyWith(fontSize: 19, color: warn ? c.warning : c.textPrimary))),
            ],
          ),
          const SizedBox(height: 12),
          SoftProgressBar(value: volume.ratio, height: 7, colors: warn ? [c.warning, const Color(0xFFFF8A3D)] : null),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('已用 ${formatBytes(volume.used)}', style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 11)),
              const Spacer(),
              Text('可用 ${formatBytes(volume.total - volume.used)}', style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiskRow extends StatelessWidget {
  final DiskInfo disk;
  const _DiskRow({required this.disk});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(Icons.storage_rounded, size: 19, color: c.textTertiary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(disk.id.toUpperCase(), style: context.texts.titleSmall?.copyWith(fontSize: 13.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${disk.model.isEmpty ? '硬盘' : disk.model} · ${formatBytes(disk.size)}',
                  style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (disk.temperature > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: (disk.temperature > 50 ? c.warning : c.success).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${disk.temperature.toStringAsFixed(0)}°C', style: context.texts.labelSmall?.copyWith(color: disk.temperature > 50 ? c.warning : c.success, fontSize: 10.5)),
            ),
          const SizedBox(width: 8),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: disk.status == 'normal' ? c.success : c.warning, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}
