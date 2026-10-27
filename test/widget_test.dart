import 'dart:convert';
import 'dart:io';

import 'package:cinema_client/core/app_models.dart';
import 'package:cinema_client/core/app_scope.dart';
import 'package:cinema_client/core/app_settings.dart';
import 'package:cinema_client/core/app_theme.dart';
import 'package:cinema_client/data/api_client.dart';
import 'package:cinema_client/data/home_cache.dart';
import 'package:cinema_client/data/local_store.dart';
import 'package:cinema_client/quark/quark_account_store.dart';
import 'package:cinema_client/quark/quark_playback_service.dart';
import 'package:cinema_client/screens/app_shell.dart';
import 'package:cinema_client/screens/detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures/vod_fixtures.dart';

class _MemoryHomeCache extends HomeCache {
  _MemoryHomeCache() : super(Directory('unused'));

  @override
  Future<HomeFeed?> read(AppSettings settings) async => null;

  @override
  Future<void> write(AppSettings settings, HomeFeed feed) async {}
}

void main() {
  testWidgets('home renders real list content and capability-neutral missing metadata', (tester) async {
    SharedPreferences.setMockInitialValues({'vod_api_base': 'http://127.0.0.1:8765'});
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings.load(prefs);
    final api = VodApi(
      settings: settings,
      client: MockClient((_) async => http.Response.bytes(
            utf8.encode(jsonEncode(homeJson)),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          )),
    );
    final services = AppServices(
      settings: settings,
      api: api,
      store: LocalStore.load(prefs),
      homeCache: _MemoryHomeCache(),
      quark: QuarkPlaybackService(
        accountStore: const QuarkAccountStore(),
        supportDirectory: Directory('unused'),
      ),
    );
    final feed = HomeFeed(
      fourK: const [
        VodItem(key: 'verified__sample_movie', name: '测试电影', mediaType: MediaKind.movie, year: 2026),
      ],
      latest: const [
        VodItem(key: 'verified__sample_tv', name: '测试剧集', mediaType: MediaKind.tv, year: 2025),
      ],
    );
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: buildCinemaTheme(),
          home: AppShell(initialHome: feed),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('测试电影'), findsWidgets);
    expect(find.text('继续观看'), findsNothing);
    await tester.tap(find.text('电视剧').first);
    await tester.pump();
    expect(find.text('测试剧集'), findsWidgets);
    expect(find.textContaining('海报'), findsNothing);
    api.close();
  });

  testWidgets('detail scroll viewport fills an iPhone-sized screen', (tester) async {
    SharedPreferences.setMockInitialValues({'vod_api_base': 'http://127.0.0.1:8765'});
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings.load(prefs);
    final api = VodApi(
      settings: settings,
      client: MockClient((request) async {
        final body = request.url.path == '/api/detail' ? detailJson : homeJson;
        return http.Response.bytes(
          utf8.encode(jsonEncode(body)),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final services = AppServices(
      settings: settings,
      api: api,
      store: LocalStore.load(prefs),
      homeCache: _MemoryHomeCache(),
      quark: QuarkPlaybackService(
        accountStore: const QuarkAccountStore(),
        supportDirectory: Directory('unused'),
      ),
    );
    final item = VodItem.fromDetailJson(detailJson['item'] as Map<String, dynamic>);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: buildCinemaTheme(),
          home: DetailScreen(item: item),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('剧集').evaluate().isNotEmpty) break;
    }
    expect(find.text('剧集'), findsOneWidget);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scrollable.position.viewportDimension, greaterThan(700));
    expect(tester.getRect(find.text('播放')).top, lessThan(844));
    api.close();
  });
}
