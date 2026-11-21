import 'package:flutter/material.dart';

import '../dsm/models.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';

class FileVisual {
  final IconData icon;
  final List<Color> colors;
  final String label;
  const FileVisual(this.icon, this.colors, this.label);
}

FileVisual visualFor(FileKind kind, {String extension = ''}) {
  switch (kind) {
    case FileKind.folder:
      return const FileVisual(Icons.folder_rounded, [Color(0xFF6FB6FF), Color(0xFF2F7CFF)], '文件夹');
    case FileKind.image:
      return const FileVisual(Icons.image_rounded, [Color(0xFFB79BFF), Color(0xFF8A6BFF)], '图片');
    case FileKind.video:
      return const FileVisual(Icons.movie_rounded, [Color(0xFF6EC6FF), Color(0xFF3F8CFF)], '视频');
    case FileKind.audio:
      return const FileVisual(Icons.music_note_rounded, [Color(0xFFFF9FB6), Color(0xFFFF6E93)], '音频');
    case FileKind.document:
      if (extension == 'pdf') {
        return const FileVisual(Icons.picture_as_pdf_rounded, [Color(0xFFFF8A7A), Color(0xFFFF5A44)], 'PDF');
      }
      if (['xls', 'xlsx', 'csv', 'numbers'].contains(extension)) {
        return const FileVisual(Icons.table_chart_rounded, [Color(0xFF5BD8A5), Color(0xFF1FB980)], '表格');
      }
      if (['ppt', 'pptx', 'key'].contains(extension)) {
        return const FileVisual(Icons.slideshow_rounded, [Color(0xFFFFB86B), Color(0xFFFF8F2E)], '演示文稿');
      }
      if (['doc', 'docx', 'pages', 'rtf'].contains(extension)) {
        return const FileVisual(Icons.description_rounded, [Color(0xFF6FA9FF), Color(0xFF3D78F0)], '文档');
      }
      return const FileVisual(Icons.article_rounded, [Color(0xFF9BA9C6), Color(0xFF6D7C9A)], '文件');
    case FileKind.archive:
      return const FileVisual(Icons.folder_zip_rounded, [Color(0xFFFFD46B), Color(0xFFFFAF1F)], '压缩包');
    case FileKind.other:
      return const FileVisual(Icons.insert_drive_file_rounded, [Color(0xFFB4BDD1), Color(0xFF8B96AE)], '文件');
  }
}

class FileEntryTile extends StatelessWidget {
  final FileEntry entry;
  final VoidCallback? onTap;
  final VoidCallback? onMore;
  final bool showMore;
  final Widget? trailing;

  const FileEntryTile({
    super.key,
    required this.entry,
    this.onTap,
    this.onMore,
    this.showMore = true,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final visual = visualFor(entry.kind, extension: entry.extension);
    final subtitle = entry.isDir
        ? '文件夹'
        : [formatBytes(entry.size), if (entry.mtime != null) formatDate(entry.mtime)].join(' · ');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      onLongPress: onMore,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(colors: visual.colors),
                boxShadow: [
                  BoxShadow(color: visual.colors.last.withValues(alpha: 0.24), blurRadius: 12, offset: const Offset(0, 5)),
                ],
              ),
              child: Icon(visual.icon, size: 21, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    style: context.texts.titleSmall?.copyWith(fontSize: 14.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: tabular(context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 11)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (showMore)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onMore,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.more_horiz_rounded, size: 19, color: c.textTertiary),
                ),
              )
            else if (entry.isDir)
              Icon(Icons.chevron_right_rounded, size: 18, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// 文件页顶部的分类胶囊。
class CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const CategoryChip({super.key, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.primary : c.surface,
          borderRadius: BorderRadius.circular(13),
          boxShadow: selected
              ? [BoxShadow(color: c.primary.withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 6))]
              : c.cardShadow,
        ),
        child: Text(
          label,
          style: context.texts.labelMedium?.copyWith(
            fontSize: 12,
            color: selected ? Colors.white : c.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
