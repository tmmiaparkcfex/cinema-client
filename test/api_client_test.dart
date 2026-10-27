import 'dart:convert';

import 'package:cinema_client/core/app_models.dart';
import 'package:cinema_client/core/app_settings.dart';
import 'package:cinema_client/data/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures/vod_fixtures.dart';

Future<AppSettings> _settings() async {
  SharedPreferences.setMockInitialValues({
    'vod_api_base': 'http://127.0.0.1:8765',
  });
  return AppSettings.load(await SharedPreferences.getInstance());
}

void main() {
  test(
    'TV detail merges real season descriptors only for the same work ID',
    () async {
      final initial =
          jsonDecode(jsonEncode(detailJson)) as Map<String, dynamic>;
      (initial['item'] as Map)['workId'] = 'tmdb:tv:2';
      final episode = jsonDecode(
        jsonEncode((initial['lines'] as List).first['entries'][0]),
      ) as Map<String, dynamic>;
      (episode['resource'] as Map)
        ..['id'] = 'season-2-episode-1'
        ..['season'] = 2;
      final api = VodApi(
        settings: await _settings(),
        client: MockClient((request) async {
          final body = request.url.path == '/api/detail'
              ? initial
              : {
                  'items': [
                    {
                      'key': 'season-2',
                      'name': '测试剧集',
                      'workId': 'tmdb:tv:2',
                      'mediaType': 'tv',
                      'coverage': {'expected': 1},
                      'sources': [
                        {
                          'lines': [
                            {
                              'group': '普通主线',
                              'preview': [episode],
                            },
                          ],
                        },
                      ],
                    },
                    {
                      'key': 'unrelated',
                      'name': '测试剧集',
                      'workId': 'tmdb:tv:999',
                      'mediaType': 'tv',
                      'sources': [],
                    },
                  ],
                  'page': 1,
                  'pagecount': 1,
                };
          return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
        }),
      );
      final detail = await api.fetchDetail('season-1');
      expect(detail.lines.single.entries, hasLength(3));
      expect(detail.allEntries.map((e) => e.season).toSet(), {1, 2});
      expect(detail.episodeCounts, {1: 2, 2: 1});
      expect(detail.seasonsLoaded, true);
      api.close();
    },
  );

  test('season lookup failure preserves selected-season playback and marks missing discovery', () async {
    final initial = jsonDecode(jsonEncode(detailJson)) as Map<String, dynamic>;
    (initial['item'] as Map)['workId'] = 'tmdb:tv:2';
    final api = VodApi(
      settings: await _settings(),
      client: MockClient(
        (r) async => r.url.path == '/api/detail'
            ? http.Response.bytes(utf8.encode(jsonEncode(initial)), 200)
            : http.Response('{}', 503),
      ),
    );
    final detail = await api.fetchDetail('season-1');
    expect(detail.allEntries, hasLength(2));
    expect(detail.seasonsLoaded, false);
    api.close();
  });

  test('same canonical work shows once while unrelated same-name works stay separate', () {
    final feed = HomeFeed.fromJson({
      'fourK': [
        {
          'key': 'season-1',
          'workId': 'tmdb:tv:2',
          'name': 'same',
          'mediaType': 'tv',
        },
        {
          'key': 'season-2',
          'workId': 'tmdb:tv:2',
          'name': 'same',
          'mediaType': 'tv',
        },
        {
          'key': 'different',
          'workId': 'tmdb:tv:3',
          'name': 'same',
          'mediaType': 'tv',
        },
      ],
    });
    expect(feed.all, hasLength(2));
  });
  test(
    'complete scrape metadata is retained separately for posters and backdrops',
    () {
      final item = VodItem.fromCatalogJson({
        'key': 'title',
        'name': 'Title',
        'mediaType': 'movie',
        'poster': 'https://example.invalid/poster.jpg',
        'backdrop': 'https://example.invalid/backdrop.jpg',
        'genres': ['剧情', '悬疑'],
        'runtimeMinutes': 124,
        'overview': 'Synopsis',
        'actors': 'Actor',
        'directors': 'Director',
        'score': '8.5',
      });
      final restored = VodItem.fromCacheJson(item.toCacheJson());
      expect(restored.poster, endsWith('poster.jpg'));
      expect(restored.backdrop, endsWith('backdrop.jpg'));
      expect(restored.genres, ['剧情', '悬疑']);
      expect(restored.runtimeMinutes, 124);
      expect(restored.actors, 'Actor');
      expect(restored.directors, 'Director');
      expect(restored.overview, 'Synopsis');
    },
  );
  test(
    'home parsing keeps only real API metadata and tolerates empty poster',
    () async {
      final settings = await _settings();
      final api = VodApi(
        settings: settings,
        client: MockClient((request) async {
          expect(request.url.path, '/api/home');
          return http.Response.bytes(
            utf8.encode(jsonEncode(homeJson)),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final feed = await api.fetchHome();
      expect(feed.fourK, hasLength(1));
      expect(feed.latest.single.name, '测试剧集');
      expect(feed.fourK.single.poster, isNull);
      expect(feed.fourK.single.overview, isEmpty);
      expect(feed.fourK.single.year, 2026);
      api.close();
    },
  );

  test('list and search use the documented query parameters', () async {
    final settings = await _settings();
    final requests = <Uri>[];
    final api = VodApi(
      settings: settings,
      client: MockClient((request) async {
        requests.add(request.url);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'ok': true,
              'items': <Object>[],
              'total': 0,
              'page': 1,
              'pagecount': 1,
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await api.fetchList(MediaKind.tv, page: 2);
    await api.search('钢铁侠');
    expect(requests[0].path, '/api/list');
    expect(requests[0].queryParameters, {'type': 'tv', 'pg': '2'});
    expect(requests[1].path, '/api/search');
    expect(requests[1].queryParameters, {'wd': '钢铁侠', 'pg': '1'});
    api.close();
  });

  test('detail preserves episode and measured resource fields', () async {
    final settings = await _settings();
    final api = VodApi(
      settings: settings,
      client: MockClient((request) async {
        expect(request.url.queryParameters['id'], 'verified__sample_tv');
        return http.Response.bytes(
          utf8.encode(jsonEncode(detailJson)),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final detail = await api.fetchDetail('verified__sample_tv');
    expect(detail.item.isTv, isTrue);
    expect(detail.lines.single.entries, hasLength(2));
    final second = detail.lines.single.entries[1].resource!;
    expect(second.episode, 2);
    expect(second.sharePassword, 'abcd');
    expect(second.bitDepth, 10);
    expect(second.technicalSummary, contains('3840×2160'));
    api.close();
  });

  test('unknown mediaType is not silently coerced to a movie', () {
    final feed = HomeFeed.fromJson({
      'fourK': [
        {
          'key': 'verified__unresolved',
          'name': '未识别条目',
          'year': null,
          'mediaType': null,
          'pics': <String>[],
          'remarks': <String>[],
          'score': '',
        },
      ],
      'latest': <Object>[],
      'stats': <String, Object>{},
    });
    expect(feed.fourK.single.mediaType, MediaKind.unknown);
    expect(feed.fourK.single.isResolved, isFalse);
    expect(feed.fourK.single.typeLabel, '类型待补齐');
  });

  test('server error is surfaced as an explicit failure', () async {
    final settings = await _settings();
    final api = VodApi(
      settings: settings,
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(jsonEncode({'ok': false, 'error': '数据库忙'})),
          503,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    await expectLater(
      api.fetchHome(),
      throwsA(
        isA<ApiException>().having((e) => e.kind, 'kind', ApiFailureKind.http),
      ),
    );
    api.close();
  });
}
