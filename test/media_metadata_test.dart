import 'dart:convert';
import 'dart:io';

import 'package:cinema_client/core/app_models.dart';
import 'package:cinema_client/core/media_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final type in ['movie', 'tv']) {
    test(
      'reads current vod-web $type metadata and retains it in the cache',
      () {
        final json = jsonDecode(
          File('test/fixtures/metadata_${type}_snapshot.json')
              .readAsStringSync(),
        ) as Map<String, dynamic>;
        final item = VodDetail.fromJson(json).item;
        final metadata = json['item']['metadata'] as Map;
        expect(item.runtimeMinutes, metadata['runtimeMinutes']);
        expect(item.metadata.credits, isNotEmpty);
        expect(item.metadata.credits.first.portrait, startsWith('https://'));
        expect(item.metadata.originalTitle, metadata['originalTitle']);
        final restored = VodItem.fromCacheJson(item.toCacheJson());
        expect(restored.workId, item.workId);
        expect(restored.runtimeMinutes, item.runtimeMinutes);
        expect(
          restored.metadata.credits.first.name,
          item.metadata.credits.first.name,
        );
        expect(
          restored.metadata.episodeData.length,
          item.metadata.episodeData.length,
        );
      },
    );
  }

  test('episode information is matched by both season and episode', () {
    final metadata = MediaMetadata.fromJson({}, [
      {'season': 1, 'episode': 1, 'name': '第一季首集'},
      {'season': 2, 'episode': 1, 'name': '第二季首集'},
    ]);
    expect(metadata.episode(2, 1)?.name, '第二季首集');
    expect(metadata.episode(1, 2), isNull);
  });

  test('missing metadata stays empty and numeric strings are accepted', () {
    final empty = MediaMetadata.fromJson(null, null);
    expect(empty.credits, isEmpty);
    expect(empty.runtimeMinutes, isNull);
    expect(empty.episode(1, 1), isNull);
    final metadata = MediaMetadata.fromJson(
      {'runtimeMinutes': '89'},
      [
        {'season': '1', 'episode': '2', 'runtimeSeconds': '2820'},
      ],
    );
    expect(metadata.runtimeMinutes, 89);
    expect(metadata.episode(1, 2)?.runtimeMinutes, 47);
  });
}
