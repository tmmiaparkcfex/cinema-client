import 'package:flutter/material.dart';

import '../core/app_models.dart';

class PosterArtwork extends StatelessWidget {
  const PosterArtwork({
    super.key,
    required this.item,
    this.borderRadius = 8,
    this.compact = false,
  });

  final VodItem item;
  final double borderRadius;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final fallback = _PosterFallback(item: item, compact: compact);
    Widget child = fallback;
    final poster = item.poster;
    if (poster != null && poster.startsWith('http')) {
      child = Image.network(
        poster,
        fit: BoxFit.cover,
        cacheWidth: 600,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (context, image, progress) =>
            progress == null ? image : fallback,
      );
    }
    return ClipRRect(
      borderRadius: radius,
      child: ColoredBox(color: const Color(0xFF151922), child: child),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback({required this.item, required this.compact});

  final VodItem item;
  final bool compact;

  static const _palettes = <List<Color>>[
    [Color(0xFF202A3B), Color(0xFF7D4D36), Color(0xFF14161B)],
    [Color(0xFF1A2F31), Color(0xFF785D39), Color(0xFF111416)],
    [Color(0xFF30242D), Color(0xFF5D3D45), Color(0xFF15151B)],
    [Color(0xFF20242F), Color(0xFF3B536A), Color(0xFF101216)],
  ];

  @override
  Widget build(BuildContext context) {
    final palette = _palettes[item.name.hashCode.abs() % _palettes.length];
    final character = item.name.isEmpty ? '影' : item.name.substring(0, 1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 180.0;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 270.0;
        return Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: palette,
                ),
              ),
            ),
            Positioned(
              right: -width * 0.12,
              top: -height * 0.05,
              child: Container(
                width: width * 0.9,
                height: width * 0.9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.14),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: -width * 0.5,
              bottom: -height * 0.05,
              child: Transform.rotate(
                angle: -0.24,
                child: Container(
                  width: width * 1.4,
                  height: height * 0.28,
                  color: Colors.black.withValues(alpha: 0.22),
                ),
              ),
            ),
            Align(
              alignment: const Alignment(0.6, -0.05),
              child: Text(
                character,
                style: TextStyle(
                  fontSize: compact ? width * 0.45 : width * 0.58,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
            ),
            Positioned(
              left: compact ? 10 : 12,
              right: compact ? 10 : 12,
              bottom: compact ? 10 : 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.name,
                    maxLines: compact ? 1 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 14 : 17,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      shadows: const [
                        Shadow(color: Colors.black87, blurRadius: 8),
                      ],
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 5),
                    Text(
                      item.year == null ? '资料待补齐' : '${item.year} · 资料待补齐',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.62),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: 1,
                height: height * 0.28,
                color: Colors.white.withValues(alpha: 0.16),
              ),
            ),
          ],
        );
      },
    );
  }
}

class BackdropArtwork extends StatelessWidget {
  const BackdropArtwork({super.key, required this.item});

  final VodItem item;

  @override
  Widget build(BuildContext context) {
    final poster = item.backdrop ?? item.poster;
    if (poster != null && poster.startsWith('http')) {
      return Image.network(
        poster,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _backdropFallback(),
        loadingBuilder: (context, image, progress) =>
            progress == null ? image : _backdropFallback(),
      );
    }
    return _backdropFallback();
  }

  Widget _backdropFallback() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B303A), Color(0xFF664333), Color(0xFF0A0B0F)],
        ),
      ),
      child: Center(
        child: Text(
          item.name.isEmpty ? '影院' : item.name,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.08),
            fontSize: 58,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
