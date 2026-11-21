import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../dsm/dsm_client.dart';
import '../dsm/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/feedback.dart';
import '../widgets/surfaces.dart';
import '../widgets/ui_kit.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _account;
  late final TextEditingController _password;
  late final TextEditingController _otp;

  bool _https = false;
  bool _trustSelfSigned = true;
  bool _autoLogin = true;
  bool _savePassword = true;
  bool _obscure = true;
  bool _advanced = false;
  bool _showOtp = false;
  bool _loading = false;
  String? _error;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final saved = context.read<AppState>().server;
    _host = TextEditingController(text: saved?.host ?? '');
    _port = TextEditingController(text: saved?.port ?? '5000');
    _account = TextEditingController(text: saved?.account ?? '');
    _password = TextEditingController(text: saved?.password ?? '');
    _otp = TextEditingController();
    _https = saved?.https ?? false;
    _trustSelfSigned = saved?.trustSelfSigned ?? true;
    _autoLogin = saved?.autoLogin ?? true;
    _showOtp = (context.read<AppState>().bootError ?? '').contains('两步验证');
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _account.dispose();
    _password.dispose();
    _otp.dispose();
    super.dispose();
  }

  void _fill(DsmServer server) {
    setState(() {
      _host.text = server.host;
      _port.text = server.port;
      _account.text = server.account;
      _password.text = server.password ?? '';
      _https = server.https;
      _trustSelfSigned = server.trustSelfSigned;
      _autoLogin = server.autoLogin;
      _error = null;
      _showOtp = false;
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final hostText = _host.text.trim();
    if (hostText.isEmpty) {
      setState(() => _error = '请输入群晖设备的 IP 或域名');
      return;
    }
    if (_account.text.trim().isEmpty) {
      setState(() => _error = '请输入 DSM 账号');
      return;
    }
    if (_password.text.isEmpty) {
      setState(() => _error = '请输入 DSM 密码');
      return;
    }

    var host = hostText;
    var port = _port.text.trim().isEmpty ? (_https ? '5001' : '5000') : _port.text.trim();
    var https = _https;
    if (host.contains('://')) {
      final uri = Uri.tryParse(host);
      if (uri != null && uri.host.isNotEmpty) {
        https = uri.scheme == 'https';
        host = uri.host;
        if (uri.hasPort) port = '${uri.port}';
      }
    }
    host = host.replaceAll(RegExp(r'/.*$'), '');
    final colon = host.lastIndexOf(':');
    if (colon > 0 && RegExp(r'^\d+$').hasMatch(host.substring(colon + 1))) {
      port = host.substring(colon + 1);
      host = host.substring(0, colon);
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final server = DsmServer(
      host: host,
      port: port,
      https: https,
      trustSelfSigned: _trustSelfSigned,
      account: _account.text.trim(),
      password: _savePassword ? _password.text : null,
      autoLogin: _autoLogin,
      rememberPassword: _savePassword,
    );

    try {
      await context.read<AppState>().signIn(
            server,
            password: _password.text,
            otp: _otp.text.trim(),
            savePassword: _savePassword,
          );
      if (!mounted) return;
      showToast(context, '已连接 $host');
    } on DsmException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        if (e.needOtp) _showOtp = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '登录失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = context.watch<AppState>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: PageScaffold(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(22, 18, 22, 28 + MediaQuery.of(context).viewInsets.bottom),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const BrandMark(size: 46),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('群晖助手', style: context.texts.titleLarge),
                        const SizedBox(height: 2),
                        Text('私有云控制台 · 飞牛风格', style: context.texts.labelSmall?.copyWith(color: c.textTertiary, letterSpacing: 0.2)),
                      ],
                    ),
                    const Spacer(),
                    const GlassBadge(icon: Icons.verified_user_rounded, label: 'DSM 6 / 7'),
                  ],
                ),
                const SizedBox(height: 34),
                Text('连接你的群晖', style: context.texts.displayMedium),
                const SizedBox(height: 8),
                Text(
                  '输入地址即可像飞牛 App 一样管理文件、下载与设备状态。\n黑群晖与官方设备同样适用。',
                  style: context.texts.bodySmall?.copyWith(color: c.textSecondary, height: 1.6, fontSize: 13),
                ),
                const SizedBox(height: 22),
                SoftCard(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                  child: Column(
                    children: [
                      _FieldRow(
                        icon: Icons.lan_rounded,
                        label: '服务器地址',
                        controller: _host,
                        hint: '192.168.1.10',
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() => _error = null),
                      ),
                      _Divider(),
                      _FieldRow(
                        icon: Icons.tag_rounded,
                        label: '端口',
                        controller: _port,
                        hint: '5000',
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                      ),
                      _Divider(),
                      _FieldRow(
                        icon: Icons.person_outline_rounded,
                        label: '账号',
                        controller: _account,
                        hint: 'DSM 登录账号',
                        textInputAction: TextInputAction.next,
                      ),
                      _Divider(),
                      _FieldRow(
                        icon: Icons.lock_outline_rounded,
                        label: '密码',
                        controller: _password,
                        hint: 'DSM 登录密码',
                        obscure: _obscure,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        trailing: IconButton(
                          splashRadius: 18,
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 19, color: c.textTertiary),
                        ),
                      ),
                      if (_showOtp) ...[
                        _Divider(),
                        _FieldRow(
                          icon: Icons.shield_outlined,
                          label: '动态码',
                          controller: _otp,
                          hint: '两步验证的 6 位动态码',
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                        ),
                      ],
                      _Divider(),
                      _AdvancedOptions(
                        expanded: _advanced,
                        https: _https,
                        trustSelfSigned: _trustSelfSigned,
                        autoLogin: _autoLogin,
                        savePassword: _savePassword,
                        onToggle: () => setState(() => _advanced = !_advanced),
                        onHttps: (v) => setState(() => _https = v),
                        onTrust: (v) => setState(() => _trustSelfSigned = v),
                        onAutoLogin: (v) => setState(() => _autoLogin = v),
                        onSavePassword: (v) => setState(() => _savePassword = v),
                      ),
                    ],
                  ),
                ),
                if (_error != null || state.bootError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: c.danger.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline_rounded, size: 17, color: c.danger),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error ?? state.bootError!, style: context.texts.bodySmall?.copyWith(color: c.danger, height: 1.45))),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  height: 53,
                  child: FilledButton(
                    onPressed: _loading ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: c.primary,
                      disabledBackgroundColor: c.primary.withValues(alpha: 0.55),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                      elevation: 0,
                    ),
                    child: _loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.login_rounded, size: 19),
                              const SizedBox(width: 8),
                              Text('登录设备', style: context.texts.titleSmall?.copyWith(color: Colors.white)),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: TextButton.icon(
                    onPressed: _loading
                        ? null
                        : () async {
                            await context.read<AppState>().enterDemo();
                          },
                    icon: Icon(Icons.explore_outlined, size: 17, color: c.textSecondary),
                    label: Text('没有设备？先体验演示模式', style: context.texts.labelLarge?.copyWith(color: c.textSecondary)),
                  ),
                ),
                if (state.servers.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Text('已保存的设备', style: context.texts.titleSmall?.copyWith(fontSize: 14)),
                      const Spacer(),
                      Text('${state.servers.length} 台', style: context.texts.labelSmall?.copyWith(color: c.textTertiary)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final server in state.servers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _SavedServerTile(
                        server: server,
                        onTap: () => _fill(server),
                      ),
                    ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(child: _FeaturePill(icon: Icons.folder_rounded, label: '文件管理', color: const Color(0xFF2F7CFF))),
                    const SizedBox(width: 10),
                    Expanded(child: _FeaturePill(icon: Icons.download_rounded, label: '下载中心', color: const Color(0xFF16C08E))),
                    const SizedBox(width: 10),
                    Expanded(child: _FeaturePill(icon: Icons.monitor_heart_rounded, label: '资源监控', color: const Color(0xFF8A6BFF))),
                  ],
                ),
                const SizedBox(height: 22),
                Center(
                  child: Text(
                    '数据仅在本机与你的设备之间传输',
                    style: context.texts.labelSmall?.copyWith(color: c.textTertiary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Divider(height: 1, thickness: 1, color: c.border.withValues(alpha: 0.7), indent: 4);
  }
}

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _FeaturePill({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: context.isDark ? 0.05 : 0.7)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: context.texts.labelSmall?.copyWith(color: c.textSecondary, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;

  const _FieldRow({
    required this.icon,
    required this.label,
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 58,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 17, color: c.textSecondary),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5)),
                const SizedBox(height: 1),
                TextField(
                  controller: controller,
                  obscureText: obscure,
                  keyboardType: keyboardType,
                  textInputAction: textInputAction,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  cursorColor: c.primary,
                  style: context.texts.bodyLarge?.copyWith(fontSize: 15),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: hint,
                    hintStyle: context.texts.bodyMedium?.copyWith(color: c.textTertiary.withValues(alpha: 0.8), fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _AdvancedOptions extends StatelessWidget {
  final bool expanded;
  final bool https;
  final bool trustSelfSigned;
  final bool autoLogin;
  final bool savePassword;
  final VoidCallback onToggle;
  final ValueChanged<bool> onHttps;
  final ValueChanged<bool> onTrust;
  final ValueChanged<bool> onAutoLogin;
  final ValueChanged<bool> onSavePassword;

  const _AdvancedOptions({
    required this.expanded,
    required this.https,
    required this.trustSelfSigned,
    required this.autoLogin,
    required this.savePassword,
    required this.onToggle,
    required this.onHttps,
    required this.onTrust,
    required this.onAutoLogin,
    required this.onSavePassword,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(Icons.tune_rounded, size: 17, color: c.textTertiary),
                const SizedBox(width: 8),
                Text('高级设置', style: context.texts.labelMedium?.copyWith(color: c.textSecondary)),
                const Spacer(),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: Icon(Icons.expand_more_rounded, size: 18, color: c.textTertiary),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 240),
          crossFadeState: expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Column(
            children: [
              _SwitchRow(label: '使用 HTTPS 连接', subtitle: '自签证书请保持下方开关开启', value: https, onChanged: onHttps),
              if (https) _SwitchRow(label: '忽略证书校验', subtitle: '适用于群晖默认自签名证书', value: trustSelfSigned, onChanged: onTrust),
              _SwitchRow(label: '自动登录', subtitle: '打开 App 时自动连接这台设备', value: autoLogin, onChanged: onAutoLogin),
              _SwitchRow(label: '记住密码', subtitle: '密码仅保存在本机', value: savePassword, onChanged: onSavePassword),
            ],
          ),
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({required this.label, required this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.texts.labelLarge),
                Text(subtitle, style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged, activeTrackColor: c.primary),
        ],
      ),
    );
  }
}

class _SavedServerTile extends StatelessWidget {
  final DsmServer server;
  final VoidCallback onTap;
  const _SavedServerTile({required this.server, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: SoftCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        shadow: false,
        color: c.surface,
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [c.primary.withValues(alpha: 0.16), c.primary.withValues(alpha: 0.06)]),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.dns_rounded, size: 20, color: c.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(server.displayName, style: context.texts.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    '${server.account}@${server.host}:${server.port}${server.https ? ' · HTTPS' : ''}',
                    style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}
