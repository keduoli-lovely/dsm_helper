import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ShareOptions {
  final int days;
  final String? password;
  final int? times;
  const ShareOptions({required this.days, this.password, this.times});
}

/// 文件/图片共用的一套共享链接设置。
Future<ShareOptions?> showShareOptions(BuildContext context, {required String fileName}) {
  return showModalBottomSheet<ShareOptions>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ShareSheet(fileName: fileName),
  );
}

class _ShareSheet extends StatefulWidget {
  final String fileName;
  const _ShareSheet({required this.fileName});

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  int _days = 0;
  bool _passwordEnabled = false;
  bool _timesEnabled = false;
  final _password = TextEditingController();
  final _times = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _times.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(color: c.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(26))),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(color: c.textTertiary.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 14),
                Text('创建共享链接', textAlign: TextAlign.center, style: context.texts.titleLarge),
                const SizedBox(height: 4),
                Text(widget.fileName, textAlign: TextAlign.center, style: context.texts.bodySmall?.copyWith(color: c.textTertiary)),
                const SizedBox(height: 18),
                Text('有效期', style: context.texts.labelLarge?.copyWith(fontSize: 12.5, color: c.textSecondary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final item in const [(0, '永久'), (1, '1 天'), (7, '7 天'), (30, '30 天')])
                      _DayChip(label: item.$2, selected: _days == item.$1, onTap: () => setState(() => _days = item.$1)),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('密码保护', style: context.texts.titleSmall?.copyWith(fontSize: 13.5)),
                  subtitle: Text('访问者需要输入密码', style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5)),
                  value: _passwordEnabled,
                  onChanged: (value) => setState(() => _passwordEnabled = value),
                ),
                if (_passwordEnabled)
                  TextField(controller: _password, decoration: const InputDecoration(hintText: '设置访问密码')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('限制访问次数', style: context.texts.titleSmall?.copyWith(fontSize: 13.5)),
                  subtitle: Text('访问达到次数后链接失效', style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5)),
                  value: _timesEnabled,
                  onChanged: (value) => setState(() => _timesEnabled = value),
                ),
                if (_timesEnabled)
                  TextField(
                    controller: _times,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '允许访问次数，例如 10'),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    final password = _passwordEnabled ? _password.text.trim() : null;
                    final times = _timesEnabled ? int.tryParse(_times.text.trim()) : null;
                    Navigator.pop(
                      context,
                      ShareOptions(
                        days: _days,
                        password: password == null || password.isEmpty ? null : password,
                        times: times != null && times > 0 ? times : null,
                      ),
                    );
                  },
                  child: const Text('创建链接'),
                ),
                const SizedBox(height: 8),
                Text(
                  '有效期与访问次数由群晖共享链接服务执行；密码会一并写入链接配置。',
                  textAlign: TextAlign.center,
                  style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DayChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: selected ? c.primary : c.surfaceAlt, borderRadius: BorderRadius.circular(11)),
        child: Text(label, style: context.texts.labelMedium?.copyWith(fontSize: 12, color: selected ? Colors.white : c.textSecondary)),
      ),
    );
  }
}
