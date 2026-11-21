import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../dsm/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icon_tile.dart';
import '../widgets/surfaces.dart';
import '../widgets/ui_kit.dart';

class MonitorPage extends StatefulWidget {
  const MonitorPage({super.key});

  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  final List<double> _cpuHistory = [];
  final List<double> _memHistory = [];
  final List<double> _rxHistory = [];
  final List<double> _txHistory = [];
  Utilization? _util;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sample();
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _sample());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _sample() async {
    final service = context.read<AppState>().service;
    if (service == null) return;
    try {
      final util = await service.utilization();
      if (!mounted) return;
      setState(() {
        if (_cpuHistory.isEmpty) _seed(util);
        _util = util;
        _append(_cpuHistory, util.cpuPercent);
        _append(_memHistory, util.memPercent);
        _append(_rxHistory, util.netRx);
        _append(_txHistory, util.netTx);
      });
    } catch (_) {}
  }

  /// 首次进入时铺满一段历史曲线，避免图表一开始是空白。
  void _seed(Utilization util) {
    for (var i = 0; i < 30; i++) {
      final wave = 0.82 + 0.18 * (0.5 + 0.5 * math.sin(i / 3.2));
      _cpuHistory.add((util.cpuPercent * wave).clamp(1, 100));
      _memHistory.add((util.memPercent * (0.97 + 0.03 * math.sin(i / 4))).clamp(1, 100));
      _rxHistory.add(util.netRx * (0.55 + 0.45 * (0.5 + 0.5 * math.sin(i / 2.6))));
      _txHistory.add(util.netTx * (0.5 + 0.5 * (0.5 + 0.5 * math.cos(i / 3.1))));
    }
  }

  void _append(List<double> list, double value) {
    list.add(value);
    if (list.length > 42) list.removeAt(0);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = context.watch<AppState>();
    final util = _util;
    final info = state.systemInfo;
    final memGb = util == null ? '—' : (util.memUsedBytes / 1024 / 1024 / 1024).toStringAsFixed(1);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PageScaffold(
        child: Column(
          children: [
            DetailHeader(
              title: '资源监控',
              subtitle: '每 2 秒自动刷新',
              actions: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: c.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: c.success, shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                      Text('实时', style: context.texts.labelSmall?.copyWith(color: c.success, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [
                  SoftCard(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            RingGauge(value: (util?.cpuPercent ?? 0) / 100, label: 'CPU 使用率', size: 118, stroke: 9),
                            RingGauge(
                              value: (util?.memPercent ?? 0) / 100,
                              label: '内存',
                              size: 118,
                              stroke: 9,
                              valueText: memGb,
                              subText: memGb == '—' ? null : 'GB',
                              color: const Color(0xFF6C8BFF),
                              endColor: const Color(0xFF9BB0FF),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(child: _SpeedPill(icon: Icons.arrow_downward_rounded, label: '下载', value: formatSpeed(util?.netRx ?? 0), color: c.primary)),
                            const SizedBox(width: 10),
                            Expanded(child: _SpeedPill(icon: Icons.arrow_upward_rounded, label: '上传', value: formatSpeed(util?.netTx ?? 0), color: const Color(0xFF16C08E))),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SoftCard(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text('CPU 趋势', style: context.texts.titleMedium),
                            const Spacer(),
                            Text('${(util?.cpuPercent ?? 0).toStringAsFixed(0)}%', style: tabular(context.texts.labelLarge?.copyWith(color: c.primary))),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 96,
                          child: CustomPaint(
                            painter: _LinePainter(
                              values: _cpuHistory.isEmpty ? [0, 0] : _cpuHistory,
                              color: c.primary,
                              maxValue: 100,
                              gridColor: c.border,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SoftCard(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text('网络吞吐', style: context.texts.titleMedium),
                            const Spacer(),
                            _LegendDot(color: c.primary, label: '下行'),
                            const SizedBox(width: 10),
                            _LegendDot(color: const Color(0xFF16C08E), label: '上行'),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 96,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _LinePainter(
                                    values: _rxHistory.isEmpty ? [0, 0] : _rxHistory,
                                    color: c.primary,
                                    maxValue: _maxOf([..._rxHistory, ..._txHistory]),
                                    gridColor: c.border,
                                    fill: true,
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _LinePainter(
                                    values: _txHistory.isEmpty ? [0, 0] : _txHistory,
                                    color: const Color(0xFF16C08E),
                                    maxValue: _maxOf([..._rxHistory, ..._txHistory]),
                                    gridColor: c.border,
                                    fill: false,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SoftCard(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Column(
                      children: [
                        InfoRow(label: '硬盘读取', value: formatSpeed(util?.diskRead ?? 0)),
                        Divider(height: 1, color: c.border.withValues(alpha: 0.6)),
                        InfoRow(label: '硬盘写入', value: formatSpeed(util?.diskWrite ?? 0)),
                        Divider(height: 1, color: c.border.withValues(alpha: 0.6)),
                        InfoRow(label: '磁盘繁忙', value: '${(util?.diskUtil ?? 0).toStringAsFixed(0)}%'),
                        Divider(height: 1, color: c.border.withValues(alpha: 0.6)),
                        InfoRow(label: '运行时间', value: info == null ? '—' : formatUptime(info.uptime)),
                        Divider(height: 1, color: c.border.withValues(alpha: 0.6)),
                        InfoRow(label: 'CPU 温度', value: info == null || info.temperature <= 0 ? '—' : '${info.temperature.toStringAsFixed(0)} °C'),
                        Divider(height: 1, color: c.border.withValues(alpha: 0.6)),
                        InfoRow(label: '处理器', value: info?.cpuModel.isNotEmpty == true ? info!.cpuModel : '${info?.cpuCores ?? '—'} 核'),
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

  double _maxOf(List<double> values) {
    if (values.isEmpty) return 1;
    final max = values.reduce((a, b) => a > b ? a : b);
    return max < 64 * 1024 ? 64 * 1024 : max * 1.2;
  }
}

class _SpeedPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _SpeedPill({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10)),
              Text(value, style: tabular(context.texts.labelLarge?.copyWith(fontSize: 12, color: c.textPrimary))),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: context.texts.labelSmall?.copyWith(color: context.colors.textTertiary, fontSize: 10)),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double maxValue;
  final Color gridColor;
  final bool fill;

  _LinePainter({required this.values, required this.color, required this.maxValue, required this.gridColor, this.fill = true});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || maxValue <= 0) return;
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint..color = gridColor.withValues(alpha: i == 3 ? 0.8 : 0.35));
    }

    final step = size.width / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = step * i;
      final y = size.height - (values[i] / maxValue).clamp(0.0, 1.0) * (size.height - 4) - 2;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    if (fill) {
      final fillPath = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        fillPath,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, 0),
            Offset(0, size.height),
            [color.withValues(alpha: 0.22), color.withValues(alpha: 0.0)],
          ),
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // 末端圆点
    final lastX = step * (values.length - 1);
    final lastY = size.height - (values.last / maxValue).clamp(0.0, 1.0) * (size.height - 4) - 2;
    canvas.drawCircle(Offset(lastX, lastY), 3, Paint()..color = color);
    canvas.drawCircle(Offset(lastX, lastY), 6, Paint()..color = color.withValues(alpha: 0.18));
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.values != values || old.maxValue != maxValue || old.color != color;
}
