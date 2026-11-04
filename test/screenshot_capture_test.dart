import 'dart:async';
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
import 'package:cinema_client/data/download_manager.dart';
import 'package:cinema_client/quark/quark_account_store.dart';
import 'package:cinema_client/quark/quark_playback_service.dart';
import 'package:cinema_client/screens/app_shell.dart';
import 'package:cinema_client/screens/detail_screen.dart';
import 'package:cinema_client/quark/quark_login_screen.dart';
import 'package:cinema_client/player/playback_screen.dart';
import 'package:cinema_client/player/player_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _capture = bool.fromEnvironment('CAPTURE_SCREENSHOTS');
const _fontPath = String.fromEnvironment(
  'SCREENSHOT_FONT',
  defaultValue: 'assets/fonts/NotoSansSC.ttf',
);
const _iconFontPath = String.fromEnvironment(
  'SCREENSHOT_ICON_FONT',
  defaultValue: 'D:/Codex/tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
);
const _output = String.fromEnvironment(
  'SCREENSHOT_OUTPUT',
  defaultValue: 'D:/Codex/01_对话项目/Codex手机任务/cinema-client/docs/screenshots',
);

const _imageDirectory = String.fromEnvironment('SCREENSHOT_IMAGE_DIR');

// Render cached artwork without live-network timers in the widget test zone.
class _ImageClient implements HttpClient {
  _ImageClient(this.images);
  final Map<String, List<int>> images;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _ImageRequest(images[url.toString()]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageRequest implements HttpClientRequest {
  _ImageRequest(this.bytes);
  final List<int>? bytes;
  @override
  Future<HttpClientResponse> close() async => _ImageResponse(bytes);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageResponse extends Stream<List<int>> implements HttpClientResponse {
  _ImageResponse(this.bytes);
  final List<int>? bytes;
  @override
  int get statusCode => bytes == null ? 404 : 200;
  @override
  int get contentLength => bytes?.length ?? 0;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes ?? const []).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
  if (_capture) {
    TestWidgetsFlutterBinding.ensureInitialized();
    final images = <String, List<int>>{};
    final manifestFile = File('$_imageDirectory/manifest.json');
    if (_imageDirectory.isNotEmpty && manifestFile.existsSync()) {
      final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map;
      for (final entry in manifest.entries) {
        final image = File('$_imageDirectory/${entry.value}');
        if (image.existsSync()) {
          images[entry.key as String] = image.readAsBytesSync();
        }
      }
    }
    setUp(
      () => debugNetworkImageHttpClientProvider = () => _ImageClient(images),
    );
    tearDown(() => debugNetworkImageHttpClientProvider = null);
  }
  FlutterSecureStorage.setMockInitialValues({});
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
      final cupertinoLoader =
          FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
            rootBundle.load(
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
          );
      await cupertinoLoader.load();
    });

    final titles = [
      for (final path in [
        'test/fixtures/metadata_tv_snapshot.json',
        'test/fixtures/metadata_movie_snapshot.json',
      ])
        VodItem.fromDetailJson(
          (jsonDecode(File(path).readAsStringSync())
                  as Map<String, dynamic>)['item']
              as Map<String, dynamic>,
        ),
    ];
    final feed = HomeFeed(fourK: titles, latest: titles);
    final snapshot = feed.toCacheJson();

    SharedPreferences.setMockInitialValues({
      'vod_api_base': 'http://127.0.0.1:8765',
    });
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings.load(prefs);
    final api = VodApi(
      settings: settings,
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(jsonEncode(snapshot)),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    final services = AppServices(
      settings: settings,
      api: api,
      store: LocalStore.load(prefs),
      homeCache: _MemoryHomeCache(),
      downloads: DownloadManager(
        prefs: prefs,
        directory: Directory('unused'),
        connect: (_, _) async =>
            throw StateError('No transfer during UI render'),
      ),
      quark: QuarkPlaybackService(
        accountStore: const QuarkAccountStore(),
        supportDirectory: Directory('unused'),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
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

    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -470),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _save(tester, boundaryKey, 'home_rows_iphone_testrender.png');

    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, 600),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('搜索').first);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await _save(tester, boundaryKey, 'search_iphone_testrender.png');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('片库').last);
    await tester.pumpAndSettle();
    await _save(tester, boundaryKey, 'catalog_iphone_testrender.png');
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    await _save(tester, boundaryKey, 'profile_iphone_testrender.png');
    await tester.tap(find.text('点击登录'));
    await tester.pumpAndSettle();
    await _save(tester, boundaryKey, 'login_iphone_testrender.png');
    await tester.tap(find.text('密码登录  ›'));
    await tester.pumpAndSettle();
    await _save(tester, boundaryKey, 'password_iphone_testrender.png');
    await tester.tap(find.text('忘记密码？'));
    await tester.pumpAndSettle();
    await _save(tester, boundaryKey, 'password_reset_iphone_testrender.png');
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('验证码登录'));
    await tester.pumpAndSettle();
    await _save(tester, boundaryKey, 'code_iphone_testrender.png');
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('我的收藏'));
    await tester.pumpAndSettle();
    await _save(tester, boundaryKey, 'library_iphone_testrender.png');
    Navigator.of(tester.element(find.text('片单还是空的'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await _save(tester, boundaryKey, 'settings_iphone_testrender.png');
    await tester.tap(find.text('播放设置'));
    await tester.pumpAndSettle();
    await _save(tester, boundaryKey, 'playback_settings_iphone_testrender.png');
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('帮助与反馈'));
    await tester.pumpAndSettle();
    await _save(tester, boundaryKey, 'help_iphone_testrender.png');
    await tester.tap(find.text('意见反馈'));
    await tester.pumpAndSettle();
    await _save(tester, boundaryKey, 'feedback_iphone_testrender.png');
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('我的下载'));
    await tester.pumpAndSettle();
    await _save(tester, boundaryKey, 'downloads_iphone_testrender.png');
    await tester.pumpWidget(const SizedBox.shrink());
    services.downloads?.dispose();

    api.close();
    debugNetworkImageHttpClientProvider = null;
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
      final cupertinoLoader =
          FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
            rootBundle.load(
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
          );
      await cupertinoLoader.load();
    });

    final detailJson = jsonDecode(
      File('test/fixtures/metadata_tv_snapshot.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final item = VodItem.fromDetailJson(
      detailJson['item'] as Map<String, dynamic>,
    );

    SharedPreferences.setMockInitialValues({
      'vod_api_base': 'http://127.0.0.1:8765',
    });
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings.load(prefs);
    final api = VodApi(
      settings: settings,
      client: MockClient((request) async {
        if (request.url.path == '/api/search') {
          return http.Response('{"ok":true,"items":[],"pagecount":1}', 200);
        }
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
      downloads: DownloadManager(
        prefs: prefs,
        directory: Directory('unused'),
        connect: (_, _) async =>
            throw StateError('No transfer during UI render'),
      ),
      quark: QuarkPlaybackService(
        accountStore: const QuarkAccountStore(),
        supportDirectory: Directory('unused'),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
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
      if (find.text('全部剧集 ›').evaluate().isNotEmpty) break;
    }
    expect(find.text('全部剧集 ›'), findsWidgets);
    await tester.pump(const Duration(milliseconds: 800));
    await _save(tester, boundaryKey, 'detail_iphone_testrender.png');

    await tester.scrollUntilVisible(
      find.text('全部剧集 ›').last,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 500));
    await _save(tester, boundaryKey, 'detail_episodes_iphone_testrender.png');
    await tester.scrollUntilVisible(
      find.text('演职人员').last,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _save(tester, boundaryKey, 'detail_cast_iphone_testrender.png');
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _screenshotTheme(),
          home: QuarkLoginScreen(playbackService: services.quark),
        ),
      ),
    );
    await tester.pump();
    await _save(tester, boundaryKey, 'cookie_iphone_testrender.png');
    await tester.binding.setSurfaceSize(const Size(844, 390));
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildCinemaPlayerTheme().copyWith(
            textTheme: buildCinemaPlayerTheme().textTheme.apply(
              fontFamily: 'ScreenshotCJK',
            ),
          ),
          home: Scaffold(
            backgroundColor: Colors.black,
            body: PlaybackControls(
              visible: true,
              title: item.name,
              subtitle: '第1季 第1集 · 原画',
              position: const Duration(minutes: 12),
              duration: const Duration(minutes: 47),
              buffer: const Duration(minutes: 15),
              playing: false,
              rate: 1,
              compact: false,
              onBack: () {},
              onToggleControls: () {},
              onTogglePlay: () async {},
              onSeekRelative: (_) async {},
              onSeekStart: (_) {},
              onSeekChanged: (_) {},
              onSeekEnd: (_) {},
              onRate: () {},
              onEpisodes: () {},
              onTracks: () {},
              onFit: () {},
              onLines: () {},
              onInfo: () {},
              onLock: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await _save(tester, boundaryKey, 'player_controls_iphone_testrender.png');
    services.downloads?.dispose();
    api.close();
    debugNetworkImageHttpClientProvider = null;
  }, skip: !_capture);
}

Future<void> _save(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
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
