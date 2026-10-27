import 'package:cinema_client/core/app_theme.dart';
import 'package:cinema_client/player/playback_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('landscape iPhone controls fit, activate playback, and seek', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(844, 390));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var played = 0;
    var seek = 0;
    var tracks = 0;
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
            onSeekRelative: (seconds) async {
              seek += seconds;
            },
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
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.tap(find.byIcon(Icons.forward_10_rounded));
    await tester.tap(find.text('音轨与字幕'));
    expect(played, 1);
    expect(seek, 10);
    expect(tracks, 1);
    expect(find.text('12:00'), findsOneWidget);
    expect(find.text('48:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
