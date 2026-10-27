import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

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
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _capture = bool.fromEnvironment('CAPTURE_SCREENSHOTS');
const _fontPath = String.fromEnvironment(
  'SCREENSHOT_FONT',
  defaultValue: 'C:/Windows/Fonts/Deng.ttf',
);
const _iconFontPath = String.fromEnvironment(
  'SCREENSHOT_ICON_FONT',
  defaultValue: 'D:/Codex/tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
);
const _output = String.fromEnvironment(
  'SCREENSHOT_OUTPUT',
  defaultValue: 'D:/Codex/01_对话项目/Codex手机任务/cinema-client/docs/screenshots',
);

class _MemoryHomeCache extends HomeCache {
  _MemoryHomeCache() : super(Directory('unused'));

  @override
  Future<HomeFeed?> read(AppSettings settings) async => null;

  @override
  Future<void> write(AppSettings settings, HomeFeed feed) async {}
}

ThemeData _screenshotTheme() {
  final theme = buildCinemaTheme();
  final buttonText = TextStyle(
    fontFamily: 'ScreenshotCJK',
    fontWeight: FontWeight.w700,
  );
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'ScreenshotCJK'),
    primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'ScreenshotCJK'),
    filledButtonTheme: FilledButtonThemeData(
      style: theme.filledButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll(buttonText),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: theme.outlinedButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll(buttonText),
      ),
    ),
  );
}

void main() {
  testWidgets('capture iPhone-sized UI render', (tester) async {
    final fontFile = File(_fontPath);
    if (!fontFile.existsSync()) {
      throw StateError('Screenshot font not found: $_fontPath');
    }
    final fontBytes = fontFile.readAsBytesSync();
    final iconFontFile = File(_iconFontPath);
    if (!iconFontFile.existsSync()) {
      throw StateError('Material icon font not found: $_iconFontPath');
    }
    final iconFontBytes = iconFontFile.readAsBytesSync();
    await tester.runAsync(() async {
      final textLoader = FontLoader('ScreenshotCJK')
        ..addFont(Future.value(ByteData.sublistView(fontBytes)));
      await textLoader.load();
      final iconLoader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(iconFontBytes)));
      await iconLoader.load();
    });

    final snapshot = jsonDecode(
      File('test/fixtures/live_home_snapshot.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final feed = HomeFeed.fromJson(snapshot);

    SharedPreferences.setMockInitialValues({'vod_api_base': 'http://127.0.0.1:8765'});
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings.load(prefs);
    final api = VodApi(
      settings: settings,
      client: MockClient((_) async => http.Response.bytes(
            utf8.encode(jsonEncode(snapshot)),
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

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: AppScope(
          services: services,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: _screenshotTheme(),
            builder: (context, child) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(
                  padding: const EdgeInsets.only(top: 47, bottom: 28),
                  viewPadding: const EdgeInsets.only(top: 47, bottom: 28),
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: AppShell(initialHome: feed),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await _save(tester, boundaryKey, 'home_iphone_testrender.png');

    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -470));
    await tester.pump(const Duration(milliseconds: 300));
    await _save(tester, boundaryKey, 'home_rows_iphone_testrender.png');

    api.close();
  }, skip: !_capture);

  testWidgets('capture iPhone-sized detail render', (tester) async {
    final fontFile = File(_fontPath);
    final iconFontFile = File(_iconFontPath);
    if (!fontFile.existsSync() || !iconFontFile.existsSync()) {
      throw StateError('Screenshot fonts not found');
    }
    final fontBytes = fontFile.readAsBytesSync();
    final iconFontBytes = iconFontFile.readAsBytesSync();
    await tester.runAsync(() async {
      final textLoader = FontLoader('ScreenshotCJK')
        ..addFont(Future.value(ByteData.sublistView(fontBytes)));
      await textLoader.load();
      final iconLoader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(iconFontBytes)));
      await iconLoader.load();
    });

    final detailJson = jsonDecode(
      File('test/fixtures/live_detail_snapshot.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final item = VodItem.fromDetailJson(detailJson['item'] as Map<String, dynamic>);

    SharedPreferences.setMockInitialValues({'vod_api_base': 'http://127.0.0.1:8765'});
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings.load(prefs);
    final api = VodApi(
      settings: settings,
      client: MockClient((request) async {
        if (request.url.path == '/api/detail') {
          return http.Response.bytes(
            utf8.encode(jsonEncode(detailJson)),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response.bytes(
          utf8.encode(jsonEncode({'ok': false, 'error': 'not found'})),
          404,
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

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: AppScope(
          services: services,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: _screenshotTheme(),
            builder: (context, child) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(
                  padding: const EdgeInsets.only(top: 47, bottom: 28),
                  viewPadding: const EdgeInsets.only(top: 47, bottom: 28),
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: DetailScreen(item: item),
          ),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('剧集').evaluate().isNotEmpty) break;
    }
    expect(find.text('剧集'), findsWidgets);
    await tester.pump(const Duration(milliseconds: 800));
    await _save(tester, boundaryKey, 'detail_iphone_testrender.png');

    await tester.scrollUntilVisible(
      find.text('剧集').last,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 500));
    await _save(tester, boundaryKey, 'detail_episodes_iphone_testrender.png');
    api.close();
  }, skip: !_capture);
}

Future<void> _save(WidgetTester tester, GlobalKey key, String name) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  });
  if (bytes == null) throw StateError('PNG encoding failed');
  final directory = Directory(_output)..createSync(recursive: true);
  File('${directory.path}/$name').writeAsBytesSync(bytes);
  // This is a Flutter test render, not a device screenshot.
  expect(File('${directory.path}/$name').lengthSync(), greaterThan(1000));
}
