import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'surfaces.dart';

class NavItemData {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const NavItemData({required this.icon, required this.activeIcon, required this.label});
}

const kNavItems = <NavItemData>[
  NavItemData(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: '首页'),
  NavItemData(icon: Icons.folder_outlined, activeIcon: Icons.folder_rounded, label: '文件'),
  NavItemData(icon: Icons.cloud_download_outlined, activeIcon: Icons.cloud_download_rounded, label: '下载'),
  NavItemData(icon: Icons.grid_view_outlined, activeIcon: Icons.grid_view_rounded, label: '应用'),
  NavItemData(icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, label: '我的'),
];

/// 悬浮式底部导航，参考飞牛 App 的 Dock 栏。
class AppBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const AppBottomNav({super.key, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FrostedBar(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            for (var i = 0; i < kNavItems.length; i++)
              Expanded(
                child: _NavCell(
                  item: kNavItems[i],
                  selected: i == index,
                  onTap: () => onChanged(i),
                  color: c.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavCell extends StatelessWidget {
  final NavItemData item;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  const _NavCell({required this.item, required this.selected, required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final inactive = c.textTertiary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? item.activeIcon : item.icon, size: 23, color: selected ? color : inactive),
            const SizedBox(height: 3),
            Text(
              item.label,
              style: context.texts.labelSmall?.copyWith(
                fontSize: 10.5,
                color: selected ? color : inactive,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 首页/文件页通用的搜索胶囊。
class SearchPill extends StatelessWidget {
  final String hint;
  final VoidCallback? onTap;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final Widget? trailing;

  const SearchPill({
    super.key,
    this.hint = '搜索',
    this.onTap,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final inner = Row(
      children: [
        const SizedBox(width: 15),
        Icon(Icons.search_rounded, size: 21, color: c.textTertiary),
        const SizedBox(width: 9),
        Expanded(
          child: controller == null
              ? Text(hint, style: context.texts.bodyMedium?.copyWith(color: c.textTertiary, fontSize: 15), maxLines: 1)
              : TextField(
                  controller: controller,
                  autofocus: autofocus,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  style: context.texts.bodyLarge,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    hintText: hint,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintStyle: context.texts.bodyMedium?.copyWith(color: c.textTertiary, fontSize: 15),
                  ),
                ),
        ),
        if (trailing != null) trailing!,
        const SizedBox(width: 12),
      ],
    );
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(23),
          boxShadow: c.cardShadow,
        ),
        child: inner,
      ),
    );
  }
}
