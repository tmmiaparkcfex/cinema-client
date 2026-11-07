import 'dart:convert';
import 'dart:io';

import 'package:cinema_client/core/app_models.dart';
import 'package:cinema_client/core/app_scope.dart';
import 'package:cinema_client/core/app_settings.dart';
import 'package:cinema_client/data/api_client.dart';
import 'package:cinema_client/data/home_cache.dart';
import 'package:cinema_client/data/local_store.dart';
import 'package:cinema_client/main.dart';
import 'package:cinema_client/player/apple_playback.dart';
import 'package:cinema_client/player/rex_player_controls.dart';
import 'package:cinema_client/quark/quark_account_store.dart';
import 'package:cinema_client/quark/quark_playback_service.dart';
import 'package:cinema_client/rex/rex_detail.dart';
import 'package:cinema_client/rex/rex_metadata.dart';
import 'package:cinema_client/rex/rex_store.dart';
import 'package:cinema_client/rex/rex_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures/vod_fixtures.dart';

class _MemoryCache extends HomeCache {
  _MemoryCache() : super(Directory('unused'));
  @override
  Future<void> write(AppSettings settings, HomeFeed feed) async {}
}

void main() {
  test('original player stays default for regular 4K and E-AC-3', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    MediaResource resource(String name, {String? hdr, String? audioCodec}) =>
        MediaResource.fromJson({
          'file': {'name': name},
          'video': {'width': 3840, 'hdr': hdr, 'audioCodec': audioCodec},
        });

    expect(ApplePlayback.canOpen(resource('4K.mkv', hdr: 'HDR10')), isFalse);
    expect(
      ApplePlayback.canOpen(resource('4K.mp4', audioCodec: 'EAC3')),
      isFalse,
    );
    expect(ApplePlayback.canOpen(resource('4K.mkv', hdr: 'DV HDR10')), isTrue);
    expect(ApplePlayback.canOpen(resource('Title.2160p.DoVi.mkv')), isTrue);
    expect(
      ApplePlayback.canOpen(resource('4K.mp4', audioCodec: 'E-AC-3 JOC')),
      isTrue,
    );
  });

  test('public TVBox catalog preserves scraped art, episode data and resource choices', () async {
    SharedPreferences.setMockInitialValues({
      'vod_api_base': 'https://tv.aeu.asia/tvbox.json',
    });
    final prefs = await SharedPreferences.getInstance();
    final rawResource =
        (detailJson['lines'] as List).first['entries'][0]['resource'] as Map;
    final requests = <Uri>[];
    final api = VodApi(
      settings: AppSettings.load(prefs),
      client: MockClient((request) async {
        requests.add(request.url);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'code': 1,
              'page': 1,
              'pagecount': 1,
              'total': 1,
              'list': [
                {
                  'vod_id': 'fixture',
                  'work_id': 'tmdb:tv:2',
                  'media_type': 'tv',
                  'vod_name': '测试剧集',
                  'vod_pic': 'https://images.invalid/poster.jpg',
                  'vod_backdrop': 'https://images.invalid/hero.jpg',
                  'metadata': {
                    'artwork': {
                      'logos': [
                        {'url': 'https://images.invalid/title.png'},
                      ],
                    },
                  },
                  'episodes': [
                    {
                      'season': 1,
                      'episode': 1,
                      'name': '第一集',
                      'airDate': '2026-11-05',
                    },
                  ],
                  'resources': [
                    {...rawResource, 'group': '普通主线'},
                  ],
                },
              ],
            }),
          ),
          200,
        );
      }),
    );
    addTearDown(api.close);
    final home = await api.fetchHome();
    final item = home.all.single;
    expect(item.heroImage, 'https://images.invalid/hero.jpg');
    expect(item.titleLogo, 'https://images.invalid/title.png');
    final detail = await api.fetchDetail(item.key, includeOtherSeasons: false);
    expect(detail.item.episodeInfo(1, 1)?['name'], '第一集');
    expect(detail.allEntries.single.resource?.catalogKey, 'fixture');
    expect(
      detail.allEntries.single.apiUrl,
      'https://tv.aeu.asia/api/resource?id=resource-1',
    );
    expect(
      requests.every((uri) => uri.path == '/api.php/provide/verified/'),
      isTrue,
    );
    expect(requests.last.queryParameters['ids'], 'fixture');
  });

  testWidgets('first launch persists completion and opens the Rex navigation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'vod_api_base': 'http://fixture.invalid',
    });
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings.load(prefs);
    final api = VodApi(
      settings: settings,
      client: MockClient((request) async {
        final response = request.url.path == '/api/home'
            ? homeJson
            : request.url.path == '/api/detail'
            ? detailJson
            : {'items': []};
        return http.Response.bytes(utf8.encode(jsonEncode(response)), 200);
      }),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      CinemaApp(
        initialHome: null,
        services: AppServices(
          settings: settings,
          api: api,
          store: LocalStore.load(prefs),
          homeCache: _MemoryCache(),
          quark: QuarkPlaybackService(
            accountStore: const QuarkAccountStore(),
            supportDirectory: Directory('unused'),
          ),
        ),
        rexStore: RexStore(prefs),
      ),
    );
    expect(find.text('想看的，正在来到眼前'), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('继续'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('开始使用'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(RexStore(prefs).onboarded, isTrue);
    expect(find.textContaining('发现'), findsWidgets);
    await tester.tap(find.text('测试剧集').first);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(RexDetail)).dy, 0);
    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(find.bySemanticsLabel('收藏'), findsWidgets);
    await tester.tap(find.bySemanticsLabel('收藏').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('收藏'), findsOneWidget);
    expect(RexStore(prefs).favorites, isNotEmpty);
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.bySemanticsLabel('返回').last);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('我的').last);
    await tester.pumpAndSettle();
    expect(find.text('默认环境'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in [
    const Size(844, 390),
    const Size(1024, 768),
    const Size(320, 568),
  ]) {
    testWidgets(
      'Rex controls fit and expose playback actions at ${size.width}',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        String? selected;
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildRexTheme(),
            home: Scaffold(
              body: RexPlayerControls(
                title: '嫁金钗 · 第 1 集',
                playing: false,
                visible: true,
                position: const Duration(minutes: 10),
                duration: const Duration(minutes: 48),
                buffer: const Duration(minutes: 14),
                quality: '4K',
                rate: 1,
                locked: false,
                onBack: () {},
                onPlay: () => taps++,
                onNext: () {},
                onSeekStart: (_) {},
                onSeekChanged: (_) {},
                onSeekEnd: (_) {},
                onMenu: (label, _) => selected = label,
                onLock: () {},
              ),
            ),
          ),
        );
        await tester.tap(find.bySemanticsLabel('播放').last);
        await tester.tap(find.text('倍速'));
        expect(taps, 1);
        expect(selected, '倍速');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
