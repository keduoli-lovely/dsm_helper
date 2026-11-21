import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 飞牛风格的彩色渐变图标块（圆角方形，带轻微高光）。
class AppIconTile extends StatelessWidget {
  final IconData icon;
  final List<Color> colors;
  final double size;
  final double? iconSize;
  final bool glow;

  const AppIconTile({
    super.key,
    required this.icon,
    required this.colors,
    this.size = 56,
    this.iconSize,
    this.glow = true,
  });

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.3;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: colors.last.withValues(alpha: 0.30),
                  blurRadius: size * 0.34,
                  offset: Offset(0, size * 0.12),
                ),
              ]
            : null,
      ),
      child: Stack(
        children: [
          // 顶部高光
          Positioned(
            left: 1,
            right: 1,
            top: 1,
            height: size * 0.48,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(radius - 1)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white.withValues(alpha: 0.26), Colors.white.withValues(alpha: 0.0)],
                ),
              ),
            ),
          ),
          Center(child: Icon(icon, size: iconSize ?? size * 0.46, color: Colors.white)),
        ],
      ),
    );
  }
}

/// 圆形描边图标按钮，对应飞牛首页右上角的动作按钮。
class CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? color;
  final String? tooltip;

  const CircleIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 22,
    this.color,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: size, color: color ?? c.textPrimary),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// 进度环：飞牛首页资源监控的三枚圆环。
class RingGauge extends StatelessWidget {
  final double value; // 0..1
  final String label;
  final String? valueText;
  final String? subText;
  final double size;
  final Color? color;
  final Color? endColor;
  final double stroke;

  const RingGauge({
    super.key,
    required this.value,
    required this.label,
    this.valueText,
    this.subText,
    this.size = 96,
    this.color,
    this.endColor,
    this.stroke = 8,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final start = color ?? c.primary;
    final end = endColor ?? const Color(0xFF5C9BFF);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: value.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) {
            return SizedBox(
              width: size,
              height: size,
              child: CustomPaint(
                painter: _RingPainter(
                  value: v,
                  track: c.isDark ? c.surfaceSunken : const Color(0xFFEDF0F6),
                  start: start,
                  end: end,
                  stroke: stroke,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        valueText ?? '${(v * 100).round()}%',
                        style: context.texts.titleLarge?.copyWith(fontSize: size * 0.22, fontWeight: FontWeight.w600, letterSpacing: -0.4),
                      ),
                      if (subText != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(subText!, style: context.texts.labelSmall?.copyWith(fontSize: size * 0.125, color: c.textTertiary)),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Text(label, style: context.texts.bodySmall?.copyWith(fontSize: 13, color: c.textSecondary)),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color track;
  final Color start;
  final Color end;
  final double stroke;

  _RingPainter({required this.value, required this.track, required this.start, required this.end, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawCircle(center, radius, trackPaint);
    if (value <= 0) return;
    final sweep = 2 * 3.1415926535 * value;
    final shader = SweepGradient(
      startAngle: -3.1415926535 / 2,
      endAngle: -3.1415926535 / 2 + sweep,
      colors: [start, end],
    ).createShader(rect);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = shader;
    canvas.drawArc(rect, -3.1415926535 / 2, sweep, false, paint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.track != track || old.start != start || old.end != end || old.stroke != stroke;
}

/// 细长的进度条（存储空间、下载进度等）。
class SoftProgressBar extends StatelessWidget {
  final double value;
  final double height;
  final List<Color>? colors;
  final bool animate;
  const SoftProgressBar({super.key, required this.value, this.height = 7, this.colors, this.animate = true});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        return ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: SizedBox(
            height: height,
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: c.isDark ? c.surfaceSunken : const Color(0xFFEDF0F6))),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: value.clamp(0.0, 1.0)),
                  duration: animate ? const Duration(milliseconds: 700) : Duration.zero,
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: (maxWidth * v).clamp(0.0, maxWidth),
                        height: height,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(height),
                          gradient: LinearGradient(colors: colors ?? [c.primary, const Color(0xFF63A0FF)]),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
