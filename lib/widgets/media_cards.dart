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
                                  color: CinemaColors.red,
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
  Widget build(BuildContext context) {
    return SizedBox(
      width: 276,
      child: Material(
        color: CinemaColors.elevated,
        borderRadius: BorderRadius.circular(9),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              SizedBox(
                width: 132,
                height: 84,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PosterArtwork(item: record.toItem(), compact: true),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: record.progress,
                        minHeight: 3,
                        backgroundColor: Colors.black54,
                        color: CinemaColors.red,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 9, 4, 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        record.completed
                            ? '${record.episodeText} 已播完'
                            : record.episodeText.isEmpty
                            ? '${(record.progress * 100).round()}%'
                            : '${record.episodeText} · ${(record.progress * 100).round()}%',
                        style: const TextStyle(
                          color: CinemaColors.muted,
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        '继续观看',
                        style: TextStyle(color: CinemaColors.red, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: '从继续观看移除',
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded, size: 17),
                color: CinemaColors.faint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
