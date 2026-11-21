import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 依次浮现的入场动画，让首页像原生 App 一样有层次。
class Entrance extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration duration;
  const Entrance({super.key, required this.child, this.index = 0, this.duration = const Duration(milliseconds: 520)});

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  late final Animation<Offset> _slide = Tween(begin: const Offset(0, 0.06), end: Offset.zero)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    final delay = Duration(milliseconds: 40 + widget.index * 60);
    Future.delayed(delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// 顶部的品牌标记：渐变圆角方块 + 设备图形。
class BrandMark extends StatelessWidget {
  final double size;
  final bool glow;
  const BrandMark({super.key, this.size = 64, this.glow = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.31),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5B93FF), Color(0xFF2E67F5), Color(0xFF1B44CE)],
        ),
        boxShadow: glow
            ? [
                BoxShadow(color: const Color(0xFF2E67F5).withValues(alpha: 0.35), blurRadius: size * 0.4, offset: Offset(0, size * 0.14)),
              ]
            : null,
      ),
      child: Stack(
        children: [
          Positioned(
            left: 1,
            right: 1,
            top: 1,
            height: size * 0.5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(size * 0.3)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white.withValues(alpha: 0.28), Colors.white.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
          Center(child: _MarkGlyph(size: size * 0.5)),
        ],
      ),
    );
  }
}

class _MarkGlyph extends StatelessWidget {
  final double size;
  const _MarkGlyph({required this.size});

  @override
  Widget build(BuildContext context) {
    final w = size;
    return SizedBox(
      width: w,
      height: w,
      child: CustomPaint(painter: _GlyphPainter()),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // 圆角「盘柜」轮廓 + 两个盘位指示灯，构成易识别的 NAS 图形。
    final frame = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.085
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.14, h * 0.12, w * 0.72, h * 0.76),
        Radius.circular(w * 0.17),
      ),
      frame,
    );
    final bay = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.075
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.85);
    for (final y in [0.38, 0.62]) {
      canvas.drawLine(Offset(w * 0.27, h * y), Offset(w * 0.63, h * y), bay);
      canvas.drawCircle(
        Offset(w * 0.72, h * y),
        w * 0.035,
        Paint()..color = const Color(0xFFBFD4FF),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 磨砂标签，比如「局域网连接」。
class GlassBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const GlassBadge({super.key, required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = color ?? c.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: tint),
          const SizedBox(width: 4),
          Text(label, style: context.texts.labelSmall?.copyWith(color: tint, fontSize: 11)),
        ],
      ),
    );
  }
}

/// 顶部标题栏（返回按钮 + 标题 + 右侧动作），用于二级页面。
class DetailHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool showBack;
  final VoidCallback? onBack;
  const DetailHeader({super.key, required this.title, this.subtitle, this.actions = const [], this.showBack = true, this.onBack});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Row(
        children: [
          if (showBack)
            _RoundButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: onBack ?? () => Navigator.of(context).maybePop(),
            ),
          if (showBack) const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.texts.headlineSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitle != null)
                  Text(subtitle!, style: context.texts.bodySmall?.copyWith(color: c.textTertiary), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: c.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withValues(alpha: context.isDark ? 0.04 : 0.6)),
          boxShadow: c.cardShadow,
        ),
        child: Icon(icon, size: 18, color: c.textPrimary),
      ),
    );
  }
}

/// 通用列表行：图标块 + 标题/副标题 + 尾部。
class SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  const SettingRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = iconColor ?? c.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, size: 19, color: color),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.texts.titleSmall),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!, style: context.texts.bodySmall?.copyWith(color: c.textTertiary), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
              ),
            ),
            trailing ?? Icon(Icons.chevron_right_rounded, size: 20, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// 轻量信息行（label 左、值右）。
class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const InfoRow({super.key, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 92, child: Text(label, style: context.texts.bodySmall?.copyWith(color: c.textTertiary))),
          Expanded(
            child: Text(value, style: context.texts.bodySmall?.copyWith(color: valueColor ?? c.textPrimary, fontWeight: FontWeight.w500), textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

/// 通用的页面进入动画（避免每处都写 CupertinoPageRoute）。
Route<T> appRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// 背景模糊的对话框遮罩（用于自定义弹层）。
Widget blurBackdrop() => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: const ColoredBox(color: Color(0x33000000)),
    );

/// 一些小的排版工具。
TextStyle tabular(TextStyle? style) => (style ?? const TextStyle()).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
