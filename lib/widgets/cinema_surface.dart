import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// Shared by hero artwork and its palette reader, so the decoded hero is reused.
ImageProvider<Object> cinemaBackdropImage(String url) =>
    ResizeImage(NetworkImage(url), width: 1200);

class PosterTone extends InheritedWidget {
  const PosterTone({super.key, required this.color, required super.child});
  final Color color;
  static Color of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PosterTone>()?.color ??
      CinemaColors.background;
  static bool exists(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PosterTone>() != null;
  @override
  bool updateShouldNotify(PosterTone oldWidget) => color != oldWidget.color;
}

/// Extract a palette once per artwork, not during scrolling or video playback.
/// A single static, low resolution poster layer supplies the diffuse backdrop.
class PosterSurface extends StatefulWidget {
  const PosterSurface({super.key, this.imageUrl, required this.child});
  final String? imageUrl;
  final Widget child;
  @override
  State<PosterSurface> createState() => _PosterSurfaceState();
}

class _PosterSurfaceState extends State<PosterSurface> {
  static final _colors = <String, Color>{};
  Color _tone = const Color(0xFFD2B8AC);
  ImageStream? _stream;
  ImageStreamListener? _listener;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _readArtwork();
  }

  @override
  void didUpdateWidget(PosterSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imageUrl != oldWidget.imageUrl) _readArtwork();
  }

  void _detach() {
    final stream = _stream;
    final listener = _listener;
    _stream = null;
    _listener = null;
    if (stream != null && listener != null) stream.removeListener(listener);
  }

  void _readArtwork() {
    _detach();
    final generation = ++_generation;
    final url = widget.imageUrl;
    if (url == null || !url.startsWith('http')) {
      _tone = CinemaColors.background;
      return;
    }
    if (_colors.containsKey(url)) {
      _tone = _colors[url]!;
      return;
    }
    _tone = CinemaColors.background;
    final stream = cinemaBackdropImage(url).resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, synchronous) async {
        if (identical(_stream, stream) && identical(_listener, listener)) {
          _detach();
        }
        Color? tone;
        try {
          tone = await _imageTone(info.image);
        } catch (_) {
          // Failed artwork keeps a neutral surface; never fabricate a poster.
        } finally {
          info.dispose();
        }
        if (tone == null || !mounted || generation != _generation) return;
        if (_colors.length >= 32) _colors.remove(_colors.keys.first);
        _colors[url] = tone;
        setState(() => _tone = tone!);
      },
      onError: (Object error, StackTrace? stack) {
        if (identical(_stream, stream) && identical(_listener, listener)) {
          _detach();
        }
      },
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  static Future<Color> _imageTone(ui.Image image) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      const Rect.fromLTWH(0, 0, 32, 32),
      Paint(),
    );
    final picture = recorder.endRecording();
    final thumbnail = await picture.toImage(32, 32);
    picture.dispose();
    final bytes = await thumbnail.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    thumbnail.dispose();
    if (bytes == null) return CinemaColors.background;
    final buckets = <int, int>{};
    for (var i = 0; i < bytes.lengthInBytes; i += 4) {
      final r = bytes.getUint8(i),
          g = bytes.getUint8(i + 1),
          b = bytes.getUint8(i + 2);
      final max = [r, g, b].reduce((a, b) => a > b ? a : b);
      final min = [r, g, b].reduce((a, b) => a < b ? a : b);
      if (max < 35 || min > 225 || max - min < 18) continue;
      final key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4);
      buckets.update(key, (count) => count + 1, ifAbsent: () => 1);
    }
    if (buckets.isEmpty) return CinemaColors.background;
    final key = buckets.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    final seed = Color.fromARGB(
      255,
      ((key >> 8) & 15) * 16 + 8,
      ((key >> 4) & 15) * 16 + 8,
      (key & 15) * 16 + 8,
    );
    final hsl = HSLColor.fromColor(seed);
    return hsl
        .withSaturation(hsl.saturation.clamp(0.08, 0.23))
        .withLightness(0.80)
        .toColor();
  }

  @override
  void dispose() {
    _generation++;
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PosterTone(
    color: _tone,
    child: Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: _tone),
              if (widget.imageUrl?.startsWith('http') == true)
                ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Image(
                    image: ResizeImage(
                      NetworkImage(widget.imageUrl!),
                      width: 64,
                    ),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.lerp(
                        _tone,
                        const Color(0xFF40241C),
                        0.55,
                      )!.withValues(alpha: 0.64),
                      _tone.withValues(alpha: 0.72),
                      Color.lerp(
                        _tone,
                        Colors.white,
                        0.48,
                      )!.withValues(alpha: 0.84),
                    ],
                    stops: const [0, 0.46, 1],
                  ),
                ),
              ),
            ],
          ),
        ),
        widget.child,
      ],
    ),
  );
}

class CinemaGlass extends StatelessWidget {
  const CinemaGlass({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 24,
    this.onTap,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: 0.38),
    borderRadius: BorderRadius.circular(radius),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
}
