import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../dsm/dsm_client.dart';
import '../dsm/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icon_tile.dart';
import '../widgets/feedback.dart';
import '../widgets/surfaces.dart';
import '../widgets/ui_kit.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  List<DsmUser> _users = [];
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
      final users = await service.users();
      if (!mounted) return;
      setState(() {
        _users = users;
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

  Future<void> _editUser(DsmUser user) async {
    final description = TextEditingController(text: user.description);
    final email = TextEditingController(text: user.email);
    await showAppSheet(
      context,
      title: '编辑用户',
      subtitle: '${user.name} · 需要管理员权限',
      children: [
        TextField(controller: description, decoration: const InputDecoration(hintText: '用户描述')),
        const SizedBox(height: 10),
        TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(hintText: '邮箱')),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 15, color: context.colors.textTertiary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '账号名称、群组与停用状态请在 DSM 控制面板中修改。',
                style: context.texts.labelSmall?.copyWith(color: context.colors.textTertiary, height: 1.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            Navigator.pop(context);
            try {
              await context.read<AppState>().service!.updateUser(user.name, description: description.text.trim(), email: email.text.trim());
              if (mounted) showToast(context, '已更新 ${user.name}');
              await _load();
            } on DsmException catch (e) {
              if (mounted) showToast(context, e.message, icon: Icons.error_outline_rounded);
            }
          },
          child: const Text('保存修改'),
        ),
      ],
    );
    description.dispose();
    email.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final admins = _users.where((u) => u.group.contains('admin')).length;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PageScaffold(
        child: Column(
          children: [
            DetailHeader(
              title: '用户与权限',
              subtitle: _users.isEmpty ? null : '${_users.length} 个账号 · $admins 位管理员',
              actions: [CircleIconButton(icon: Icons.refresh_rounded, onTap: _load, size: 20)],
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
                  : _error != null
                      ? Center(child: EmptyHint(icon: Icons.cloud_off_rounded, title: '读取用户失败', subtitle: _error, action: FilledButton(onPressed: _load, child: const Text('重试'))))
                      : ListView.separated(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                          itemCount: _users.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final user = _users[index];
                            final colors = [
                              [const Color(0xFF6FB6FF), const Color(0xFF2F7CFF)],
                              [const Color(0xFFFFB86B), const Color(0xFFFF8F2E)],
                              [const Color(0xFFB79BFF), const Color(0xFF8A6BFF)],
                              [const Color(0xFF5BD8A5), const Color(0xFF1FB980)],
                              [const Color(0xFFFF9FB6), const Color(0xFFFF6E93)],
                            ][index % 5];
                            return SoftCard(
                              padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
                              radius: 20,
                              onTap: () => _editUser(user),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(colors: colors),
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    child: Center(
                                      child: Text(
                                        user.name.isEmpty ? '?' : user.name.substring(0, 1).toUpperCase(),
                                        style: context.texts.titleSmall?.copyWith(color: Colors.white, fontSize: 16),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(user.name, style: context.texts.titleSmall?.copyWith(fontSize: 14.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                                            ),
                                            if (user.group.contains('admin')) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                                                child: Text('管理员', style: context.texts.labelSmall?.copyWith(color: c.primary, fontSize: 9.5)),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          user.description.isEmpty ? (user.group.isEmpty ? '普通用户' : user.group) : user.description,
                                          style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 11),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (user.email.isNotEmpty)
                                          Text(
                                            user.email,
                                            style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(color: user.disabled ? c.textTertiary : c.success, shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    user.disabled ? '停用' : '正常',
                                    style: context.texts.labelSmall?.copyWith(color: user.disabled ? c.textTertiary : c.success, fontSize: 10),
                                  ),
                                  Icon(Icons.chevron_right_rounded, size: 18, color: c.textTertiary),
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
