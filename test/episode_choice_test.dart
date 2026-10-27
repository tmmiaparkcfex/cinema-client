import 'package:cinema_client/core/app_models.dart';
import 'package:cinema_client/core/episode_choice.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/vod_fixtures.dart';

void main() {
  test('next episode stays inside the selected line and respects order', () {
    final detail = VodDetail.fromJson(detailJson);
    final choices = EpisodeChoice.forLine(detail.lines.single);
    expect(choices.map((choice) => choice.episode), [1, 2]);
    final next = EpisodeChoice.nextEpisode(detail, choices.first);
    expect(next?.episode, 2);
    expect(EpisodeChoice.nextEpisode(detail, choices.last), isNull);
  });

  test('line switch finds the same episode', () {
    final detail = VodDetail.fromJson(detailJson);
    final line = detail.lines.single;
    final first = EpisodeChoice.forLine(line).first;
    expect(EpisodeChoice.sameEpisodeInLine(detail, line, first)?.resource?.id, 'resource-1');
  });

  test('cached home does not retain resource or share data', () {
    final feed = HomeFeed.fromJson(homeJson);
    final cached = feed.toCacheJson();
    expect(cached.toString(), isNot(contains('pan.quark.cn')));
    final restored = HomeFeed.fromJson(cached, fromCache: true);
    expect(restored.fourK.single.name, '测试电影');
  });
}
