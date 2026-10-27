import 'package:cinema_client/core/app_models.dart';
import 'package:cinema_client/core/episode_choice.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/vod_fixtures.dart';

void main() {
  MediaLine line(String group, List<(String, int)> versions) => MediaLine(
    group: group,
    entries: [
      for (final (id, episode) in versions)
        PlayEntry(
          label: id,
          apiUrl: '/api/resource?id=$id',
          group: group,
          resource: MediaResource.fromJson({
            'id': id,
            'season': 1,
            'episode': episode,
          }),
        ),
    ],
  );

  test('same episode is required when changing lines', () {
    final a = line('A', [('A-E2', 2)]);
    final b = line('B', [('B-E1', 1)]);
    final detail = VodDetail(
      item: const VodItem(key: 'tv', name: 'test', mediaType: MediaKind.tv),
      lines: [a, b],
    );
    expect(
      EpisodeChoice.sameEpisodeInLine(
        detail,
        b,
        EpisodeChoice.forLine(a).single,
      ),
      isNull,
    );
  });

  test('next episode skips alternate versions of the current episode', () {
    final a = line('A', [('E1-a', 1), ('E1-b', 1), ('E2', 2)]);
    final detail = VodDetail(
      item: const VodItem(key: 'tv', name: 'test', mediaType: MediaKind.tv),
      lines: [a],
    );
    expect(
      EpisodeChoice.nextEpisode(
        detail,
        EpisodeChoice.forLine(a).first,
      )?.episode,
      2,
    );
  });

  test(
    'same episode on another line preserves and bounds the switch position',
    () {
      final a = EpisodeChoice.forLine(line('A', [('A-E2', 2)])).single;
      final b = EpisodeChoice.forLine(line('B', [('B-E2', 2)])).single;
      expect(EpisodeChoice.isSameEpisode(a, b), true);
      final measured = MediaResource.fromJson({
        'id': 'measured',
        'video': {'durationSeconds': 20},
      });
      expect(
        EpisodeChoice.resumeWithinResource(
          const Duration(seconds: 12),
          measured,
        ),
        const Duration(seconds: 12),
      );
      expect(
        EpisodeChoice.resumeWithinResource(
          const Duration(seconds: 40),
          measured,
        ),
        const Duration(seconds: 20),
      );
      expect(
        EpisodeChoice.resumeWithinResource(
          const Duration(seconds: -1),
          measured,
        ),
        Duration.zero,
      );
    },
  );

  test('next episode stays inside the selected line and respects order', () {
    final detail = VodDetail.fromJson(detailJson);
    final choices = EpisodeChoice.forLine(detail.lines.single);
    expect(choices.map((choice) => choice.episode), [1, 2]);
    final next = EpisodeChoice.nextEpisode(detail, choices.first);
    expect(next?.episode, 2);
    expect(EpisodeChoice.nextEpisode(detail, choices.last), isNull);
  });

  test('autoplay does not silently skip a missing episode', () {
    final a = line('A', [('E1', 1), ('E3', 3)]);
    final detail = VodDetail(
      item: const VodItem(key: 'tv', name: 'test', mediaType: MediaKind.tv),
      lines: [a],
    );
    expect(
      EpisodeChoice.nextEpisode(detail, EpisodeChoice.forLine(a).first),
      isNull,
    );
  });

  test('next episode can use another available line and cross a verified season ending', () {
    final a = line('A', [('E1', 1)]);
    final b = line('B', [('E2', 2)]);
    final nextSeason = MediaLine(
      group: 'A',
      entries: [
        PlayEntry(
          label: 'S2E1',
          apiUrl: '/api/resource',
          group: 'A',
          resource: MediaResource.fromJson({
            'id': 's2e1',
            'season': 2,
            'episode': 1,
          }),
        ),
      ],
    );
    final detail = VodDetail(
      item: const VodItem(key: 'tv', name: 'test', mediaType: MediaKind.tv),
      lines: [a, b, nextSeason],
      episodeCounts: {1: 2},
    );
    final second = EpisodeChoice.nextEpisode(
      detail,
      EpisodeChoice.forLine(a).first,
    );
    expect(second?.line.group, 'B');
    final third = EpisodeChoice.nextEpisode(detail, second!);
    expect(third?.season, 2);
    expect(third?.episode, 1);
  });

  test('line switch finds the same episode', () {
    final detail = VodDetail.fromJson(detailJson);
    final line = detail.lines.single;
    final first = EpisodeChoice.forLine(line).first;
    expect(
      EpisodeChoice.sameEpisodeInLine(detail, line, first)?.resource?.id,
      'resource-1',
    );
  });

  test('cached home does not retain resource or share data', () {
    final source = {
      ...homeJson,
      'fourK': [
        {
          ...(homeJson['fourK'] as List).first as Map,
          'sources': [
            {
              'lines': [
                {'preview': (detailJson['lines'] as List).first['entries']},
              ],
            },
          ],
        },
      ],
    };
    expect(source.toString(), contains('pan.quark.cn'));
    final feed = HomeFeed.fromJson(source);
    expect(feed.fourK.single.catalogLines, isNotEmpty);
    final cached = feed.toCacheJson();
    expect(cached.toString(), isNot(contains('pan.quark.cn')));
    final restored = HomeFeed.fromJson(cached, fromCache: true);
    expect(restored.fourK.single.name, '测试电影');
    expect(restored.fourK.single.catalogLines, isEmpty);
  });
}
