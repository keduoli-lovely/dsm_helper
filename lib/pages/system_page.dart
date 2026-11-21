import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../dsm/dsm_client.dart';
import '../dsm/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icon_tile.dart';
import '../widgets/surfaces.dart';
import '../widgets/ui_kit.dart';

class SystemPage extends StatefulWidget {
  const SystemPage({super.key});

  @override
  State<SystemPage> createState() => _SystemPageState();
}

class _SystemPageState extends State<SystemPage> {
  SystemInfo? _info;
  Map<String, dynamic> _network = const {};
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
      final info = await service.systemInfo();
      Map<String, dynamic> network = const {};
      try {
        network = await service.networkInfo();
      } on DsmException catch (_) {}
      if (!mounted) return;
      setState(() {
        _info = info;
        _network = network;
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

  List<Map<String, dynamic>> get _interfaces {
    final raw = _network['interfaces'] ?? _network['ifaces'] ?? _network['adapters'];
    if (raw is List) return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final info = _info;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PageScaffold(
        child: Column(
          children: [
            DetailHeader(
              title: '系统信息',
              subtitle: info == null ? null : '${info.model} · DSM ${info.dsmLabel}',
              actions: [CircleIconButton(icon: Icons.refresh_rounded, onTap: _load, size: 20)],
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
                  : _error != null
                      ? Center(child: EmptyHint(icon: Icons.cloud_off_rounded, title: '读取失败', subtitle: _error, action: FilledButton(onPressed: _load, child: const Text('重试'))))
                      : ListView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                          children: [
                            SoftCard(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                children: [
                                  _HeroRow(label: '设备型号', value: info?.model ?? '—', icon: Icons.dns_rounded),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Expanded(child: _MiniInfo(label: 'DSM 版本', value: info?.dsmLabel ?? '—')),
                                      const SizedBox(width: 10),
                                      Expanded(child: _MiniInfo(label: '运行时间', value: info == null ? '—' : formatUptime(info.uptime))),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            _SectionCard(
                              title: '设备',
                              icon: Icons.memory_rounded,
                              rows: [
                                ('主机名称', info?.hostname.isNotEmpty == true ? info!.hostname : '—'),
                                ('序列号', info?.serial.isNotEmpty == true ? info!.serial : '—'),
                                ('处理器', info?.cpuModel.isNotEmpty == true ? info!.cpuModel : '—'),
                                ('核心数', info == null || info.cpuCores == 0 ? '—' : '${info.cpuCores} 核'),
                                ('内存', info == null || info.ramMb == 0 ? '—' : formatBytes(info.ramMb * 1024 * 1024)),
                                ('温度', info == null || info.temperature <= 0 ? '—' : '${info.temperature.toStringAsFixed(0)} °C'),
                              ],
                            ),
                            const SizedBox(height: 14),
                            SoftCard(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.lan_rounded, size: 18, color: c.primary),
                                      const SizedBox(width: 8),
                                      Text('网络', style: context.texts.titleMedium),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (_interfaces.isEmpty)
                                    Text('未获取到网络接口信息', style: context.texts.bodySmall?.copyWith(color: c.textTertiary))
                                  else
                                    for (var i = 0; i < _interfaces.length; i++) ...[
                                      if (i > 0) Divider(height: 20, color: c.border.withValues(alpha: 0.6)),
                                      _InterfaceRow(data: _interfaces[i]),
                                    ],
                                  if (_network['dns'] != null) ...[
                                    const SizedBox(height: 10),
                                    Text('DNS · ${_network['dns']}', style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5)),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            SoftCard(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Icon(Icons.verified_user_rounded, size: 18, color: c.success),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '设备状态正常。所有操作通过群晖 WebAPI 直接执行，不经过第三方服务器。',
                                      style: context.texts.bodySmall?.copyWith(color: c.textTertiary, height: 1.6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _HeroRow({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [c.primary.withValues(alpha: 0.18), c.primary.withValues(alpha: 0.06)]),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, size: 23, color: c.primary),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5)),
              const SizedBox(height: 2),
              Text(value, style: context.texts.headlineSmall?.copyWith(fontSize: 20)),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniInfo extends StatelessWidget {
  final String label;
  final String value;
  const _MiniInfo({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(13)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10)),
          const SizedBox(height: 3),
          Text(value, style: tabular(context.texts.labelLarge?.copyWith(fontSize: 12.5)), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<(String, String)> rows;
  const _SectionCard({required this.title, required this.icon, required this.rows});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: c.primary),
              const SizedBox(width: 8),
              Text(title, style: context.texts.titleMedium),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: c.border.withValues(alpha: 0.6)),
            InfoRow(label: rows[i].$1, value: rows[i].$2),
          ],
        ],
      ),
    );
  }
}

class _InterfaceRow extends StatelessWidget {
  final Map<String, dynamic> data;
  const _InterfaceRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = (data['name'] ?? data['ifname'] ?? data['device'] ?? '接口').toString();
    final ip = (data['ip'] ?? data['ipv4'] ?? '—').toString();
    final speed = (data['speed'] ?? data['max_speed'] ?? '').toString();
    final mac = (data['mac'] ?? '').toString();
    final connected = !ip.contains('未连接') && ip != '—' && ip.isNotEmpty;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(11)),
          child: Icon(Icons.settings_ethernet_rounded, size: 17, color: connected ? c.primary : c.textTertiary),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(name.toUpperCase(), style: context.texts.titleSmall?.copyWith(fontSize: 13)),
                  const SizedBox(width: 6),
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: connected ? c.success : c.textTertiary, shape: BoxShape.circle)),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                [ip, if (speed.isNotEmpty) '${speed}Mbps', if (mac.isNotEmpty) mac].join(' · '),
                style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
