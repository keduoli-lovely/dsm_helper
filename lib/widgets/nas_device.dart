import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 用 CustomPainter 绘制的迷你 NAS 主机，替代飞牛首页右侧的 3D 设备图。
class NasDevice extends StatelessWidget {
  final double width;
  final bool online;
  const NasDevice({super.key, this.width = 82, this.online = true});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: width,
      height: width * 0.92,
      child: CustomPaint(
        painter: _NasPainter(
          accent: c.primary,
          online: online,
          dark: c.isDark,
          bodyTop: c.isDark ? const Color(0xFF3A4254) : const Color(0xFF4A5468),
          bodyBottom: c.isDark ? const Color(0xFF1D222E) : const Color(0xFF232A38),
        ),
      ),
    );
  }
}

class _NasPainter extends CustomPainter {
  final Color accent;
  final Color bodyTop;
  final Color bodyBottom;
  final bool online;
  final bool dark;

  _NasPainter({required this.accent, required this.bodyTop, required this.bodyBottom, required this.online, required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 82;
    canvas.scale(scale, scale);
    final w = 82.0;
    final h = w * 0.92;

    // 底部光晕
    final glowPaint = Paint()
      ..color = accent.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(14, h - 18, w - 28, 16), const Radius.circular(8)),
      glowPaint,
    );

    final bodyRect = RRect.fromRectAndRadius(Rect.fromLTWH(10, 3, w - 20, h - 12), const Radius.circular(9));
    final bodyPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(10, 3),
        Offset(10, h - 9),
        [bodyTop, bodyBottom],
      );
    canvas.drawRRect(bodyRect, bodyPaint);

    // 顶部高光棱边
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = ui.Gradient.linear(
        const Offset(10, 2),
        Offset(w - 10, 40),
        [Colors.white.withValues(alpha: 0.55), Colors.white.withValues(alpha: 0.02)],
      );
    canvas.drawRRect(bodyRect, rim);

    // 四个硬盘位
    for (var i = 0; i < 4; i++) {
      final y = 9.0 + i * 11.5;
      final bay = RRect.fromRectAndRadius(Rect.fromLTWH(15, y, w - 30, 8.6), const Radius.circular(2.6));
      canvas.drawRRect(bay, Paint()..color = const Color(0xFF141925).withValues(alpha: dark ? 0.85 : 0.9));
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(15, y, w - 30, 3.4), const Radius.circular(2.4)),
        Paint()..color = Colors.white.withValues(alpha: 0.06),
      );
      // 盘位指示灯
      final led = Paint()
        ..color = i == 0 ? (online ? const Color(0xFF3CE2A8) : const Color(0xFFFFB020)) : accent
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4);
      canvas.drawCircle(Offset(w - 20.5, y + 4.3), 1.15, led);
    }

    // 品牌铭牌
    final plate = RRect.fromRectAndRadius(Rect.fromLTWH(15, h - 26, w - 30, 9), const Radius.circular(3));
    canvas.drawRRect(plate, Paint()..color = Colors.white.withValues(alpha: dark ? 0.06 : 0.10));
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'NAS',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.72),
          fontSize: 5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(w / 2 - textPainter.width / 2, h - 23.5));

    // 底部电源灯
    final powerLed = Paint()
      ..color = online ? const Color(0xFF3CE2A8) : const Color(0xFF8A93A6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4);
    canvas.drawCircle(Offset(w / 2, h - 14.5), 1.7, powerLed);
  }

  @override
  bool shouldRepaint(covariant _NasPainter old) =>
      old.accent != accent || old.online != online || old.dark != dark || old.bodyTop != bodyTop;
}
