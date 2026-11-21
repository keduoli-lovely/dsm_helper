import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 真实用户头像；取不到时回退到渐变色首字母。
class UserAvatar extends StatelessWidget {
  final String account;
  final String? imageUrl;
  final Map<String, String> headers;
  final double size;

  const UserAvatar({
    super.key,
    required this.account,
    this.imageUrl,
    this.headers = const {},
    this.size = 42,
  });

  static const _palettes = [
    [Color(0xFFFFC080), Color(0xFFFF9F73)],
    [Color(0xFF8FB6FF), Color(0xFF5B84F7)],
    [Color(0xFF9FE5C8), Color(0xFF4CC9A0)],
    [Color(0xFFC6B4FF), Color(0xFF9A7BF0)],
    [Color(0xFFFFB3C5), Color(0xFFFF7E9B)],
  ];

  List<Color> get _palette => _palettes[account.hashCode.abs() % _palettes.length];

  @override
  Widget build(BuildContext context) {
    final fallback = _Fallback(account: account, size: size, palette: _palette);
    final url = imageUrl;
    final avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: _palette),
        boxShadow: [BoxShadow(color: _palette.last.withValues(alpha: 0.32), blurRadius: size * 0.34, offset: Offset(0, size * 0.14))],
      ),
      child: ClipOval(
        child: url == null || url.isEmpty
            ? fallback
            : Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                headers: headers,
                errorBuilder: (_, __, ___) => fallback,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded || frame != null) return child;
                  return fallback;
                },
              ),
      ),
    );
    return avatar;
  }
}

class _Fallback extends StatelessWidget {
  final String account;
  final double size;
  final List<Color> palette;
  const _Fallback({required this.account, required this.size, required this.palette});

  @override
  Widget build(BuildContext context) {
    final initial = account.isEmpty ? '?' : account.substring(0, 1).toUpperCase();
    return Container(
      color: Colors.transparent,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(color: Colors.white, fontSize: size * 0.4, fontWeight: FontWeight.w600, height: 1),
      ),
    );
  }
}

/// 首页连接状态：已连接 / 未连接 + 网络延迟 + 局域网标识。
class ConnectionStatus extends StatelessWidget {
  final bool? online;
  final int? latencyMs;
  final bool lan;
  const ConnectionStatus({super.key, this.online, this.latencyMs, this.lan = true});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Color color;
    final String label;
    if (online == null) {
      color = c.textTertiary;
      label = '连接中…';
    } else if (online == false) {
      color = c.danger;
      label = '未连接';
    } else {
      color = latencyMs != null && latencyMs! > 500 ? c.warning : c.success;
      label = '已连接';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: context.texts.labelSmall?.copyWith(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          if (online == true && latencyMs != null) ...[
            const SizedBox(width: 5),
            Text('· $latencyMs ms', style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5)),
          ],
          if (lan) ...[
            const SizedBox(width: 5),
            Text('· 局域网', style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5)),
          ],
        ],
      ),
    );
  }
}
