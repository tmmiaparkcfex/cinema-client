import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The decoder keeps the original stream. Only the display texture is fitted
/// to physical screen pixels, instead of rendering a 4K texture on a phone.
Size displayVideoSize({
  required Size viewport,
  required double pixelRatio,
  required int sourceWidth,
  required int sourceHeight,
}) {
  final width = sourceWidth > 0 ? sourceWidth.toDouble() : 1920.0;
  final height = sourceHeight > 0 ? sourceHeight.toDouble() : 1080.0;
  final screenWidth = math.max(viewport.width, viewport.height) * pixelRatio;
  final screenHeight = math.min(viewport.width, viewport.height) * pixelRatio;
  final scale = math.min(
    1.0,
    math.min(screenWidth / width, screenHeight / height),
  );
  return Size(
    math.max(2, (width * scale).floor()).toDouble(),
    math.max(2, (height * scale).floor()).toDouble(),
  );
}

/// Video frames are rendered by the native texture. Position events must not
/// rebuild the entire Flutter player while its controls are hidden.
class PlaybackUiBudget {
  Duration _lastPaint = const Duration(days: -1);

  bool shouldPaint({required Duration elapsed, required bool visible}) {
    if (!visible || elapsed - _lastPaint < const Duration(milliseconds: 500)) {
      return false;
    }
    _lastPaint = elapsed;
    return true;
  }
}
