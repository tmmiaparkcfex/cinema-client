import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_models.dart';
import 'rex_metadata.dart';
import 'rex_theme.dart';

class RexArtwork extends StatelessWidget {
  const RexArtwork(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.label,
  });
  final String? url;
  final BoxFit fit;
  final Alignment alignment;
  final String? label;
  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: RexColors.card.withValues(alpha: .5),
      child: Center(
        child: Icon(
          CupertinoIcons.film,
          color: Colors.white.withValues(alpha: .2),
          size: 32,
        ),
      ),
    );
    if (url == null || url!.isEmpty) return placeholder;
    if (url!.startsWith('asset:')) {
      return Image.asset(
        url!.substring(6),
        fit: fit,
        alignment: alignment,
        semanticLabel: label,
        errorBuilder: (_, _, _) => placeholder,
      );
    }
    return Image.network(
      url!,
      fit: fit,
      alignment: alignment,
      semanticLabel: label,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}

class RexGlass extends StatelessWidget {
  const RexGlass({
    super.key,
    required this.child,
    this.radius = 28,
    this.color = const Color(0xAD685C6B),
  });
  final Widget child;
  final double radius;
  final Color color;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
      child: ColoredBox(color: color, child: child),
    ),
  );
}

class RexIconButton extends StatelessWidget {
  const RexIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
    this.size = 21,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: onTap,
      child: Icon(icon, color: color, size: size),
    ),
  );
}

class RexHeading extends StatelessWidget {
  const RexHeading(this.title, {super.key, this.onMore, this.trailing});
  final String title;
  final VoidCallback? onMore;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        ?trailing,
        if (onMore != null)
          RexIconButton(
            icon: CupertinoIcons.chevron_right,
            label: '更多$title',
            onTap: onMore,
            size: 17,
          ),
      ],
    ),
  );
}

class RexPoster extends StatelessWidget {
  const RexPoster({
    super.key,
    required this.item,
    required this.onTap,
    this.width = 110,
  });
  final VodItem item;
  final VoidCallback onTap;
  final double width;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: width,
              height: width * 1.5,
              child: RexArtwork(item.posterImage, label: item.name),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.white),
          ),
          Text(
            item.year?.toString() ?? '',
            style: const TextStyle(fontSize: 11, color: RexColors.muted),
          ),
        ],
      ),
    ),
  );
}

class RexPosterRow extends StatelessWidget {
  const RexPosterRow({
    super.key,
    required this.items,
    required this.onOpen,
    this.wide = false,
  });
  final List<VodItem> items;
  final ValueChanged<VodItem> onOpen;
  final bool wide;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: wide ? 171 : 211,
    child: ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      scrollDirection: Axis.horizontal,
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(width: 12),
      itemBuilder: (context, index) {
        final item = items[index];
        if (!wide) return RexPoster(item: item, onTap: () => onOpen(item));
        return SizedBox(
          width: 248,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => onOpen(item),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 248,
                    height: 124,
                    child: RexArtwork(item.heroImage),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                Text(
                  '${item.year ?? ''} · ${item.categories.join(' / ')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: RexColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class RexRatings extends StatelessWidget {
  const RexRatings(this.item, {super.key});
  final VodItem item;
  @override
  Widget build(BuildContext context) {
    final rating = item.score.isNotEmpty
        ? item.score
        : item.metadata['rating']?.toString();
    if (rating == null || rating.isEmpty) return const SizedBox(height: 12);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF35CFBD),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text(
              'TMDB',
              style: TextStyle(
                color: Color(0xFF173B39),
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            rating,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class RexTicket extends StatelessWidget {
  const RexTicket({
    super.key,
    required this.item,
    required this.onTap,
    this.label,
    this.compact = false,
  });
  final VodItem item;
  final VoidCallback onTap;
  final String? label;
  final bool compact;
  @override
  Widget build(BuildContext context) => CupertinoButton(
    padding: EdgeInsets.zero,
    onPressed: onTap,
    child: ClipPath(
      clipper: _TicketClip(),
      child: Container(
        height: compact ? 98 : 123,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF854F36), Color(0xFF4A3038)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(9),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: compact ? 52 : 65,
                  child: RexArtwork(item.posterImage),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 3,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 13 : 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      label ?? '${item.year ?? ''} · ${item.typeLabel}',
                      style: const TextStyle(
                        color: Color(0xFFD0C2BB),
                        fontSize: 11,
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 7),
                      Text(
                        item.categories.take(2).join(' / '),
                        maxLines: 1,
                        style: const TextStyle(
                          color: Color(0xFFD0C2BB),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            CustomPaint(size: const Size(42, 98), painter: _BarcodePainter()),
          ],
        ),
      ),
    ),
  );
}

class _TicketClip extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(15)),
      );
    final holes = Path()
      ..addOval(Rect.fromCircle(center: Offset(size.width - 42, 0), radius: 6))
      ..addOval(
        Rect.fromCircle(
          center: Offset(size.width - 42, size.height),
          radius: 6,
        ),
      );
    return Path.combine(PathOperation.difference, path, holes);
  }

  @override
  bool shouldReclip(_TicketClip oldClipper) => false;
}

class _BarcodePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE8DDD5)
      ..strokeWidth = 1;
    for (double y = 10; y < size.height - 10; y += 5) {
      canvas.drawLine(Offset(1, y), Offset(1, y + 2), paint);
    }
    for (var i = 0; i < 29; i++) {
      paint.strokeWidth = i % 3 == 0 ? 2 : 1;
      canvas.drawLine(
        Offset(12, 10 + i * 2.7),
        Offset(33, 10 + i * 2.7),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarcodePainter oldDelegate) => false;
}

class RexEmpty extends StatelessWidget {
  const RexEmpty(
    this.title, {
    super.key,
    this.subtitle,
    this.icon = CupertinoIcons.tv,
    this.onRetry,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(26),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 31, color: RexColors.muted),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 7),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: RexColors.muted),
          ),
        ],
        if (onRetry != null)
          CupertinoButton(onPressed: onRetry, child: const Text('重试')),
      ],
    ),
  );
}

class RexDots extends StatelessWidget {
  const RexDots({
    super.key,
    required this.count,
    required this.index,
    required this.onSelect,
  });
  final int count, index;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(
      count,
      (i) => Semantics(
        label: '第 ${i + 1} 页',
        selected: index == i,
        button: true,
        child: GestureDetector(
          onTap: () => onSelect(i),
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            height: 32,
            width: index == i ? 30 : 16,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                height: 5,
                width: index == i ? 22 : 5,
                decoration: BoxDecoration(
                  color: index == i ? Colors.white : const Color(0xFF9F909C),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
