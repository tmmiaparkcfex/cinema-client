import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_models.dart';
import '../core/app_theme.dart';
import '../data/local_store.dart';
import 'poster_artwork.dart';

class MediaCard extends StatefulWidget {
  const MediaCard({
    super.key,
    required this.item,
    required this.onTap,
    this.progress,
    this.width,
  });

  final VodItem item;
  final VoidCallback onTap;
  final double? progress;
  final double? width;

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final width = widget.width ?? (screenWidth >= 900 ? 166.0 : 128.0);
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        label: '${widget.item.name}，${widget.item.isTv ? '电视剧' : '电影'}',
        child: FocusableActionDetector(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onTap();
                return null;
              },
            ),
          },
          onFocusChange: (value) => setState(() => _focused = value),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedScale(
              scale: _focused ? 1.035 : 1,
              duration: const Duration(milliseconds: 130),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 2 / 3,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 130),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: _focused ? Colors.white : Colors.transparent,
                          width: 2,
                        ),
                        boxShadow: _focused
                            ? const [
                                BoxShadow(
                                  color: Color(0x77FFFFFF),
                                  blurRadius: 16,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          PosterArtwork(item: widget.item),
                          if (widget.item.catalogLines.any(
                            (line) => line.entries.any(
                              (entry) =>
                                  (entry.resource?.width ?? 0) >= 3840 ||
                                  (entry.resource?.height ?? 0) >= 2160,
                            ),
                          ))
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xDDFAF2E9),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '4K',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: CinemaColors.text,
                                  ),
                                ),
                              ),
                            ),
                          if (widget.progress != null && widget.progress! > 0)
                            Positioned(
                              left: 6,
                              right: 6,
                              bottom: 6,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: widget.progress!.clamp(0, 1),
                                  minHeight: 3,
                                  backgroundColor: Colors.black54,
                                  color: CinemaColors.accent,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (widget.item.year != null) '${widget.item.year}',
                      if (widget.item.genres.isNotEmpty)
                        widget.item.genres.first
                      else
                        widget.item.typeLabel,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CinemaColors.faint,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ContinueCard extends StatelessWidget {
  const ContinueCard({
    super.key,
    required this.record,
    required this.onTap,
    required this.onRemove,
  });
  final PlaybackRecord record;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    onLongPress: onRemove,
    child: Row(
      children: [
        SizedBox(
          width: MediaQuery.sizeOf(context).width * 0.43,
          height: 74,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: PosterArtwork(item: record.toItem(), compact: true),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                record.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${record.episodeText} · ${record.completed ? '已播完' : '已看 ${record.positionMs ~/ 60000} 分钟'}',
                maxLines: 1,
                style: const TextStyle(fontSize: 12, color: CinemaColors.muted),
              ),
              const SizedBox(height: 9),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: record.progress,
                  minHeight: 3,
                  color: CinemaColors.accent,
                  backgroundColor: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
