import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_log.dart';
import 'core/app_models.dart';
import 'core/app_scope.dart';
import 'core/app_settings.dart';
import 'core/app_theme.dart';
import 'data/api_client.dart';
import 'data/home_cache.dart';
import 'data/local_store.dart';
import 'quark/quark_account_store.dart';
import 'quark/quark_playback_service.dart';
import 'screens/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final supportDirectory = await getApplicationSupportDirectory();
  await AppLog.initialize(supportDirectory);

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLog.error('flutter', details.exception);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.error('platform', error);
    return false;
  };

  final prefs = await SharedPreferences.getInstance();
  final settings = AppSettings.load(prefs);
  final store = LocalStore.load(prefs);
  final cache = HomeCache(supportDirectory);
  final api = VodApi(settings: settings);
  final quark = QuarkPlaybackService(
    accountStore: const QuarkAccountStore(),
    supportDirectory: supportDirectory,
  );

  HomeFeed? initialHome;
  try {
    initialHome = await cache.read(settings);
  } catch (error) {
    AppLog.error('cache', error);
  }

  final services = AppServices(
    settings: settings,
    api: api,
    store: store,
    homeCache: cache,
    quark: quark,
  );
  runApp(CinemaApp(services: services, initialHome: initialHome));
  unawaited(quark.cleanupStale().catchError((Object error) {
    AppLog.error('quark-startup-cleanup', error);
  }));
}

class CinemaApp extends StatelessWidget {
  const CinemaApp({
    super.key,
    required this.services,
    required this.initialHome,
  });

  final AppServices services;
  final HomeFeed? initialHome;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: MaterialApp(
        title: '影院',
        debugShowCheckedModeBanner: false,
        theme: buildCinemaTheme(),
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          overscroll: false,
        ),
        home: AppShell(initialHome: initialHome),
      ),
    );
  }
}
