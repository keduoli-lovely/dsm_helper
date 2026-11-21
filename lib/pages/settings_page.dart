import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dsm/dsm_client.dart';
import '../dsm/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/feedback.dart';
import '../widgets/surfaces.dart';
import '../widgets/ui_kit.dart';
import 'logs_page.dart';
import 'storage_page.dart';
import 'system_page.dart';
import 'tasks_page.dart';
import 'users_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool? _ssh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSsh());
  }

  Future<void> _loadSsh() async {
    final service = context.read<AppState>().service;
    if (service == null) return;
    try {
      final enabled = await service.sshEnabled();
      if (mounted) setState(() => _ssh = enabled);
    } catch (_) {}
  }

  Future<void> _toggleSsh(bool value) async {
    setState(() => _ssh = value);
    try {
      await context.read<AppState>().service!.setSsh(value);
      if (mounted) showToast(context, value ? 'SSH 已开启' : 'SSH 已关闭');
    } on DsmException catch (e) {
      if (!mounted) return;
      setState(() => _ssh = !value);
      showToast(context, e.message, icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _power(String action) async {
    final isShutdown = action == 'shutdown';
    final ok = await showConfirm(
      context,
      title: isShutdown ? '确认关闭群晖？' : '确认重启群晖？',
      message: isShutdown ? '设备将安全关机，之后需要手动开机。' : '设备将在约 2 分钟后重新上线。',
      confirmText: isShutdown ? '关机' : '重启',
      danger: true,
    );
    if (!ok) return;
    try {
      await context.read<AppState>().service!.power(action);
      if (mounted) showToast(context, isShutdown ? '已发送关机指令' : '已发送重启指令');
    } on DsmException catch (e) {
      if (mounted) showToast(context, e.message, icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _openWeb() async {
    final server = context.read<AppState>().server;
    if (server == null) return;
    final ok = await launchUrl(Uri.parse(server.baseUrl), mode: LaunchMode.externalApplication);
    if (!ok && mounted) showToast(context, '无法打开浏览器', icon: Icons.error_outline_rounded);
  }

  Future<void> _signOut() async {
    final ok = await showConfirm(
      context,
      title: '退出当前设备？',
      message: '下次进入需要重新输入密码（如未保存）。',
      confirmText: '退出登录',
      danger: true,
    );
    if (!ok) return;
    await context.read<AppState>().signOut(forgetPassword: true);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.colors;
    final info = state.systemInfo;
    final storage = state.storage;
    final util = state.utilization;
    final account = state.server?.account ?? '—';
    final deviceName = info?.hostname.isNotEmpty == true ? info!.hostname : (state.server?.displayName ?? '群晖设备');

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PageScaffold(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 132),
          children: [
            Entrance(
              index: 0,
              child: Row(
                children: [
                  Text('我的', style: context.texts.displayMedium),
                  const Spacer(),
                  IconButton(
                    onPressed: _openWeb,
                    icon: Icon(Icons.open_in_new_rounded, color: c.textSecondary, size: 20),
                    tooltip: '在浏览器中打开 DSM',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Entrance(
              index: 1,
              child: SoftCard(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(colors: [Color(0xFFFFC080), Color(0xFFFF9F73)]),
                        boxShadow: [BoxShadow(color: const Color(0xFFFFAE63).withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))],
                      ),
                      child: Center(
                        child: Text(
                          account.isEmpty ? '?' : account.substring(0, 1).toUpperCase(),
                          style: context.texts.headlineSmall?.copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(account, style: context.texts.titleLarge),
                          const SizedBox(height: 3),
                          Text(deviceName, style: context.texts.bodySmall?.copyWith(color: c.textTertiary, fontSize: 12.5)),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const GlassBadge(icon: Icons.device_hub_rounded, label: 'DSM 助手'),
                              const SizedBox(width: 6),
                              if (state.demo) const GlassBadge(icon: Icons.explore_rounded, label: '演示模式', color: Color(0xFFFF9F0A)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.verified_rounded, size: 22, color: c.success),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Entrance(
              index: 2,
              child: Row(
                children: [
                  Expanded(child: _StatCard(label: '存储已用', value: storage == null ? '—' : '${(storage.ratio * 100).toStringAsFixed(0)}%', icon: Icons.storage_rounded, color: const Color(0xFF28BFA2))),
                  const SizedBox(width: 10),
                  Expanded(child: _StatCard(label: 'CPU', value: util == null ? '—' : '${util.cpuPercent.toStringAsFixed(0)}%', icon: Icons.memory_rounded, color: c.primary)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatCard(
                      label: '温度',
                      value: info == null || info.temperature <= 0 ? '—' : '${info.temperature.toStringAsFixed(0)}°',
                      icon: Icons.thermostat_rounded,
                      color: const Color(0xFFFF9F0A),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Entrance(
              index: 3,
              child: SoftCard(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  children: [
                    SettingRow(
                      icon: Icons.storage_rounded,
                      title: '存储空间',
                      subtitle: storage == null ? null : '${formatBytes(storage.usedBytes)} / ${formatBytes(storage.totalBytes)}',
                      iconColor: const Color(0xFF28BFA2),
                      onTap: () => Navigator.of(context).push(appRoute(const StoragePage())),
                    ),
                    SettingRow(
                      icon: Icons.dns_rounded,
                      title: '系统信息',
                      subtitle: info == null ? null : '${info.model} · DSM ${info.dsmLabel}',
                      iconColor: c.primary,
                      onTap: () => Navigator.of(context).push(appRoute(const SystemPage())),
                    ),
                    SettingRow(
                      icon: Icons.group_rounded,
                      title: '用户与权限',
                      iconColor: const Color(0xFFFF6E93),
                      onTap: () => Navigator.of(context).push(appRoute(const UsersPage())),
                    ),
                    SettingRow(
                      icon: Icons.receipt_long_rounded,
                      title: '系统日志',
                      iconColor: const Color(0xFFFFB020),
                      onTap: () => Navigator.of(context).push(appRoute(const LogsPage())),
                    ),
                    SettingRow(
                      icon: Icons.schedule_rounded,
                      title: '计划任务',
                      iconColor: const Color(0xFF8A6BFF),
                      onTap: () => Navigator.of(context).push(appRoute(const TasksPage())),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Entrance(
              index: 4,
              child: SoftCard(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  children: [
                    SettingRow(
                      icon: Icons.terminal_rounded,
                      title: 'SSH 服务',
                      subtitle: _ssh == null ? '读取中…' : (_ssh! ? '已开启，可在终端登录' : '已关闭'),
                      iconColor: const Color(0xFF4FA8FF),
                      trailing: Switch(value: _ssh ?? false, onChanged: _ssh == null ? null : _toggleSsh),
                      onTap: _ssh == null ? null : () => _toggleSsh(!(_ssh ?? false)),
                    ),
                    SettingRow(
                      icon: Icons.power_settings_new_rounded,
                      title: '电源管理',
                      subtitle: '关机或重启群晖设备',
                      iconColor: c.danger,
                      onTap: () => _showPowerSheet(),
                    ),
                    SettingRow(
                      icon: Icons.lock_outline_rounded,
                      title: '安全与隐私',
                      subtitle: '账号仅保存在本机',
                      iconColor: const Color(0xFF6E7A91),
                      onTap: () => showAppSheet(
                        context,
                        title: '安全与隐私',
                        children: [
                          Text(
                            '群晖助手直接通过局域网访问你的 DSM，不经过任何第三方服务器。\n\n登录密码仅保存在本机（可选择不保存），会话在退出时自动注销。',
                            style: context.texts.bodySmall?.copyWith(height: 1.7),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Entrance(
              index: 5,
              child: SoftCard(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('外观', style: context.texts.titleSmall),
                    const SizedBox(height: 12),
                    _ThemeSelector(
                      mode: state.themeMode,
                      onChanged: (mode) => state.setThemeMode(mode),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Entrance(
              index: 6,
              child: SoftCard(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  children: [
                    SettingRow(
                      icon: Icons.info_outline_rounded,
                      title: '关于群晖助手',
                      subtitle: '版本 1.0.0 · 全新飞牛风格界面',
                      iconColor: const Color(0xFF8A96AE),
                      onTap: () => showAppSheet(
                        context,
                        title: '群晖助手',
                        subtitle: '版本 1.0.0',
                        children: [
                          Text(
                            '为黑群晖与群晖用户打造的手机管理端。界面参考飞牛 fnOS App，功能基于群晖官方 WebAPI 实现。\n\n• 文件管理：浏览、上传、重命名、删除\n• 下载中心：查看、添加、暂停下载任务\n• 资源监控：CPU / 内存 / 网络 / 存储\n• 系统控制：电源、SSH、日志与用户',
                            style: context.texts.bodySmall?.copyWith(height: 1.75),
                          ),
                        ],
                      ),
                    ),
                    SettingRow(
                      icon: Icons.code_rounded,
                      title: '开源仓库',
                      subtitle: 'github.com/keduoli-lovely/dsm_helper',
                      iconColor: c.isDark ? c.textSecondary : const Color(0xFF24292F),
                      onTap: () => launchUrl(Uri.parse('https://github.com/keduoli-lovely/dsm_helper'), mode: LaunchMode.externalApplication),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Entrance(
              index: 7,
              child: SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _signOut,
                  icon: Icon(Icons.logout_rounded, size: 19, color: c.danger),
                  label: Text('退出登录', style: context.texts.titleSmall?.copyWith(color: c.danger)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: c.danger.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text('群晖助手 · DSM Helper', style: context.texts.labelSmall?.copyWith(color: c.textTertiary)),
            ),
          ],
        ),
      ),
    );
  }

  void _showPowerSheet() {
    showAppSheet(
      context,
      title: '电源管理',
      subtitle: '请确认设备当前没有正在进行的写入任务',
      children: [
        SheetAction(icon: Icons.restart_alt_rounded, label: '重启设备', subtitle: '约 2 分钟后重新上线', onTap: () {
          Navigator.pop(context);
          _power('reboot');
        }),
        SheetAction(icon: Icons.power_settings_new_rounded, label: '关闭设备', subtitle: '安全关机，需手动开机', danger: true, onTap: () {
          Navigator.pop(context);
          _power('shutdown');
        }),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(height: 8),
          Text(value, style: tabular(context.texts.titleLarge?.copyWith(fontSize: 19))),
          const SizedBox(height: 1),
          Text(label, style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5)),
        ],
      ),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;
  const _ThemeSelector({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final options = [
      (ThemeMode.light, Icons.light_mode_rounded, '浅色'),
      (ThemeMode.dark, Icons.dark_mode_rounded, '深色'),
      (ThemeMode.system, Icons.brightness_auto_rounded, '跟随系统'),
    ];
    return Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(options[i].$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: mode == options[i].$1 ? c.primary.withValues(alpha: 0.12) : c.surfaceAlt,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: mode == options[i].$1 ? c.primary.withValues(alpha: 0.35) : Colors.transparent),
                ),
                child: Column(
                  children: [
                    Icon(options[i].$2, size: 18, color: mode == options[i].$1 ? c.primary : c.textTertiary),
                    const SizedBox(height: 5),
                    Text(
                      options[i].$3,
                      style: context.texts.labelSmall?.copyWith(color: mode == options[i].$1 ? c.primary : c.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
