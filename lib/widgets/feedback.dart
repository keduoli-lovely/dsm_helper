import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 轻提示，替代系统 Toast。
void showToast(BuildContext context, String message, {IconData icon = Icons.check_circle_rounded, Color? color}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1800),
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 96),
        content: Row(
          children: [
            Icon(icon, size: 18, color: color ?? Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: context.texts.bodyMedium?.copyWith(color: Colors.white))),
          ],
        ),
      ),
    );
}

/// 统一风格的底部弹窗容器。
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<Widget> children,
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(20, 10, 20, 22),
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      final c = ctx.colors;
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: c.textTertiary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(title, style: ctx.texts.titleLarge, textAlign: TextAlign.center),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(subtitle, style: ctx.texts.bodySmall?.copyWith(color: c.textTertiary), textAlign: TextAlign.center),
              ],
              const SizedBox(height: 18),
              ...children,
              SizedBox(height: MediaQuery.of(ctx).padding.bottom),
            ],
          ),
        ),
      );
    },
  );
}

class SheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool danger;
  final Color? iconColor;
  const SheetAction({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.onTap,
    this.danger = false,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = danger ? c.danger : (iconColor ?? c.primary);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, size: 19, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: context.texts.titleSmall?.copyWith(color: danger ? c.danger : c.textPrimary)),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(subtitle!, style: context.texts.bodySmall?.copyWith(color: c.textTertiary)),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: c.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool> showConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmText = '确定',
  bool danger = false,
}) async {
  final c = context.colors;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message, style: ctx.texts.bodyMedium),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          style: TextButton.styleFrom(foregroundColor: c.textSecondary),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: TextButton.styleFrom(foregroundColor: danger ? c.danger : c.primary),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<String?> showInputDialog(
  BuildContext context, {
  required String title,
  String? hint,
  String initial = '',
  String confirmText = '确定',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint ?? '请输入名称'),
        onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('取消', style: TextStyle(color: ctx.colors.textSecondary))),
        TextButton(onPressed: () => Navigator.of(ctx).pop(controller.text.trim()), child: Text(confirmText)),
      ],
    ),
  );
  return (result == null || result.isEmpty) ? null : result;
}
