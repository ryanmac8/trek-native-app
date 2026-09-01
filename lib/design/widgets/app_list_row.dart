import 'package:flutter/material.dart';

/// Standard leading-icon/avatar + title/subtitle + trailing row, tappable.
/// The generic building block for future list screens (trips, places,
/// budget items, packing items) — [SkeletonListTile] mirrors its layout
/// for loading states.
class AppListRow extends StatelessWidget {
  const AppListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: leading,
      title: Text(title, style: textTheme.titleMedium),
      subtitle: subtitle != null
          ? Text(subtitle!, style: textTheme.bodyMedium)
          : null,
      trailing: trailing,
      onTap: onTap,
    );
  }
}
