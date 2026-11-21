import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 柔和渐变背景 + 两团低透明度光斑，贴近飞牛 App 的「空气感」。
class GradientBackdrop extends StatelessWidget {
  final Widget child;
  final bool showBlobs;
  const GradientBackdrop({super.key, required this.child, this.showBlobs = true});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: c.background),
      child: Stack(
        children: [
          if (showBlobs) ...[
            Positioned(
              top: -120,
              right: -90,
              child: _Blob(color: c.primary.withValues(alpha: context.isDark ? 0.20 : 0.14), size: 320),
            ),
            Positioned(
              top: 160,
              left: -110,
              child: _Blob(color: c.purple.withValues(alpha: context.isDark ? 0.12 : 0.10), size: 280),
            ),
          ],
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;
  const _Blob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
    );
  }
}

/// 白色大圆角卡片，带极淡的阴影；点击时轻微缩放。
class SoftCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final bool shadow;
  final Border? border;

  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = AppRadii.card,
    this.color,
    this.onTap,
    this.gradient,
    this.shadow = true,
    this.border,
  });

  @override
  State<SoftCard> createState() => _SoftCardState();
}

class _SoftCardState extends State<SoftCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final content = AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: Container(
        padding: widget.padding,
        decoration: BoxDecoration(
          color: widget.gradient == null ? (widget.color ?? c.surface) : null,
          gradient: widget.gradient,
          borderRadius: BorderRadius.circular(widget.radius),
          border: widget.border,
          boxShadow: widget.shadow ? c.cardShadow : null,
        ),
        child: widget.child,
      ),
    );
    if (widget.onTap == null) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: content,
    );
  }
}

/// 小号磨砂玻璃容器（用于悬浮导航等）。
class FrostedBar extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry padding;
  final double radius;
  const FrostedBar({
    super.key,
    required this.child,
    this.margin,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    this.radius = AppRadii.nav,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: margin,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius), boxShadow: c.navShadow),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: c.surface.withValues(alpha: context.isDark ? 0.82 : 0.88),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: Colors.white.withValues(alpha: context.isDark ? 0.04 : 0.55)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 区块标题：图标胶囊 + 标题 + 右侧动作。
class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final IconData icon;
  final Color iconColor;
  final Color? iconBg;

  const SectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onAction,
    this.icon = Icons.analytics_rounded,
    this.iconColor = const Color(0xFF2E6BFF),
    this.iconBg,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: iconBg ?? iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 10),
        Text(title, style: context.texts.titleMedium),
        const Spacer(),
        if (action != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAction,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
              child: Row(
                children: [
                  Text(action!, style: context.texts.labelMedium?.copyWith(color: c.textTertiary)),
                  Icon(Icons.chevron_right_rounded, size: 16, color: c.textTertiary),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 无内容时的占位提示。
class EmptyHint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const EmptyHint({super.key, required this.icon, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(22)),
            child: Icon(icon, size: 30, color: c.textTertiary),
          ),
          const SizedBox(height: 14),
          Text(title, style: context.texts.titleSmall?.copyWith(color: c.textSecondary)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, style: context.texts.bodySmall?.copyWith(color: c.textTertiary)),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

class PageScaffold extends StatelessWidget {
  final Widget child;
  final bool safeTop;
  const PageScaffold({super.key, required this.child, this.safeTop = true});

  @override
  Widget build(BuildContext context) {
    return GradientBackdrop(
      child: SafeArea(
        bottom: false,
        top: safeTop,
        child: child,
      ),
    );
  }
}
