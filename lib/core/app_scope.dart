import 'package:flutter/widgets.dart';

import '../data/api_client.dart';
import '../data/home_cache.dart';
import '../data/local_store.dart';
import '../quark/quark_playback_service.dart';
import 'app_settings.dart';

class AppServices {
  const AppServices({
    required this.settings,
    required this.api,
    required this.store,
    required this.homeCache,
    required this.quark,
  });

  final AppSettings settings;
  final VodApi api;
  final LocalStore store;
  final HomeCache homeCache;
  final QuarkPlaybackService quark;
}

class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.services,
    required super.child,
  });

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
