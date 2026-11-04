import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import 'cinema_surface.dart';

class ReferenceHeader extends StatelessWidget {
  const ReferenceHeader({
    super.key,
    this.onBack,
    required this.onSearch,
    required this.onMore,
    this.title = '影视',
    this.light = true,
  });
  final VoidCallback? onBack;
  final VoidCallback onSearch;
  final VoidCallback onMore;
  final String title;
  final bool light;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (onBack != null)
        CinemaGlass(
          radius: 24,
          child: IconButton(
            tooltip: '返回',
            onPressed: onBack,
            icon: const Icon(CupertinoIcons.back, size: 25),
          ),
        )
      else
        Text(
          title,
          style: TextStyle(
            fontSize: 24,
            height: 1.1,
            fontWeight: FontWeight.w700,
            color: light ? Colors.white : CinemaColors.text,
          ),
        ),
      const Spacer(),
      CinemaGlass(
        radius: 24,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '搜索',
              onPressed: onSearch,
              icon: const Icon(CupertinoIcons.search, size: 23),
            ),
            Container(
              width: 0.6,
              height: 18,
              color: CinemaColors.muted.withValues(alpha: 0.3),
            ),
            IconButton(
              tooltip: '更多',
              onPressed: onMore,
              icon: const Icon(CupertinoIcons.ellipsis, size: 25),
            ),
          ],
        ),
      ),
    ],
  );
}

class ReferencePageHeader extends StatelessWidget {
  const ReferencePageHeader({super.key, required this.title, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: CinemaGlass(
              radius: 24,
              child: IconButton(
                tooltip: '返回',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(CupertinoIcons.back, size: 24),
              ),
            ),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(width: 44, child: trailing),
        ],
      ),
    ),
  );
}

class ReferenceTabs extends StatelessWidget {
  const ReferenceTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.light = false,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;
  final bool light;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < labels.length; i++)
        Padding(
          padding: const EdgeInsets.only(right: 24),
          child: InkWell(
            onTap: () => onSelected(i),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: selected == i
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: light
                        ? Colors.white.withValues(
                            alpha: selected == i ? 1 : 0.78,
                          )
                        : CinemaColors.text,
                  ),
                ),
                const SizedBox(height: 7),
                Container(
                  height: 4,
                  width: 16,
                  decoration: BoxDecoration(
                    color: selected == i
                        ? (light ? Colors.white : CinemaColors.accent)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}
