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
  SharedPreferences.setMockInitialValues({'vod_api_base': 'http://127.0.0.1:8765'});
  return AppSettings.load(await SharedPreferences.getInstance());
}

void main() {
  test('home parsing keeps only real API metadata and tolerates empty poster', () async {
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
  });

  test('list and search use the documented query parameters', () async {
    final settings = await _settings();
    final requests = <Uri>[];
    final api = VodApi(
      settings: settings,
      client: MockClient((request) async {
        requests.add(request.url);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({'ok': true, 'items': <Object>[], 'total': 0, 'page': 1, 'pagecount': 1}),
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
      client: MockClient((_) async => http.Response.bytes(
            utf8.encode(jsonEncode({'ok': false, 'error': '数据库忙'})),
            503,
            headers: {'content-type': 'application/json; charset=utf-8'},
          )),
    );
    await expectLater(
      api.fetchHome(),
      throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiFailureKind.http)),
    );
    api.close();
  });
}
