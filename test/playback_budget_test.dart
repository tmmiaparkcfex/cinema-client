import 'package:cinema_client/player/playback_budget.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('4K remains decoded at source size but texture fits phone pixels', () {
    final result = displayVideoSize(
      viewport: const Size(390, 844),
      pixelRatio: 3,
      sourceWidth: 3840,
      sourceHeight: 2160,
    );
    expect(result, const Size(2080, 1170));
    expect(result.width / result.height, closeTo(16 / 9, 0.002));
    expect(result.width * result.height, lessThan(3840 * 2160 / 3));
  });
  test('output does not upscale a smaller source', () {
    expect(
      displayVideoSize(
        viewport: const Size(1024, 768),
        pixelRatio: 2,
        sourceWidth: 1280,
        sourceHeight: 720,
      ),
      const Size(1280, 720),
    );
  });
  test(
    'hidden controls paint zero times and visible controls at most twice/sec',
    () {
      final budget = PlaybackUiBudget();
      var paints = 0;
      for (var frame = 0; frame < 600; frame++) {
        if (budget.shouldPaint(
          elapsed: Duration(milliseconds: frame * 16),
          visible: false,
        )) {
          paints++;
        }
      }
      expect(paints, 0);
      for (var frame = 0; frame < 600; frame++) {
        if (budget.shouldPaint(
          elapsed: Duration(milliseconds: frame * 16),
          visible: true,
        )) {
          paints++;
        }
      }
      expect(paints, inInclusiveRange(18, 20));
    },
  );
}
