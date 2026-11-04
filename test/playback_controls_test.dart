import 'package:cinema_client/core/app_theme.dart';
import 'package:cinema_client/player/playback_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('landscape iPhone controls fit, activate playback, and seek', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(844, 390));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var played = 0;
    var next = 0;
    var tracks = 0;
    var locked = 0;
    var info = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCinemaTheme(),
        home: Scaffold(
          body: PlaybackControls(
            visible: true,
            title: '测试电视剧',
            subtitle: '第1季 第2集',
            position: const Duration(minutes: 12),
            duration: const Duration(minutes: 48),
            buffer: const Duration(minutes: 15),
            playing: false,
            rate: 1,
            compact: false,
            onBack: () {},
            onToggleControls: () {},
            onTogglePlay: () async {
              played++;
            },
            onSeekRelative: (seconds) async {},
            onNext: () async => next++,
            onSeekStart: (_) {},
            onSeekChanged: (_) {},
            onSeekEnd: (_) {},
            onRate: () {},
            onEpisodes: () {},
            onTracks: () {
              tracks++;
            },
            onFit: () {},
            onLines: () {},
            onLock: () => locked++,
            onInfo: () => info++,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.tap(find.byTooltip('下一集'));
    await tester.tap(find.text('音轨'));
    await tester.tap(find.byTooltip('锁定屏幕'));
    await tester.tap(find.byTooltip('播放信息'));
    expect(played, 1);
    expect(next, 1);
    expect(tracks, 1);
    expect(locked, 1);
    expect(info, 1);
    expect(find.text('12:00'), findsOneWidget);
    expect(find.text('48:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
