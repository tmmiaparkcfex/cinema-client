import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_models.dart';
import '../core/app_scope.dart';
import '../data/api_client.dart';

class RexCatalog extends ChangeNotifier {
  RexCatalog(this.services, HomeFeed? initial) : feed = initial;
  final AppServices services;
  HomeFeed? feed;
  ApiException? error;
  bool loading = false;
  int _generation = 0;
  bool _disposed = false;
  final Map<String, VodItem> _rich = {};
  List<VodItem> get items => (feed?.all ?? <VodItem>[])
      .where((v) => v.isResolved)
      .map((v) => _rich[v.identityKey] ?? v)
      .toList();

  Future<void> refresh() async {
    final generation = ++_generation;
    final base = services.settings.baseUrl;
    loading = true;
    error = null;
    _emit();
    try {
      final home = await services.api.fetchHome();
      if (!_valid(generation, base)) return;
      feed = home;
      loading = false;
      _emit();
      final extra = await Future.wait([
        for (final kind in [MediaKind.movie, MediaKind.tv])
          services.api
              .fetchList(kind)
              .then((page) => page.items)
              .catchError((Object _) => <VodItem>[]),
      ]);
      if (!_valid(generation, base)) return;
      feed = HomeFeed(
        fourK: home.fourK,
        latest: uniqueTitles([...home.latest, ...extra.expand((v) => v)]),
        stats: home.stats,
      );
      unawaited(
        services.homeCache
            .write(services.settings, feed!)
            .catchError((Object _) {}),
      );
      _emit();
      // Older catalog responses omit metadata that is already present in detail.
      // Hydrate only the visible recommendations, not the whole library.
      await Future.wait(
        items.take(4).where((item) => item.metadata.isEmpty).map((item) async {
          try {
            final detail = await services.api.fetchDetail(
              item.key,
              includeOtherSeasons: false,
            );
            if (!_valid(generation, base)) return;
            _rich[item.identityKey] = detail.item.copyWith(
              key: item.key,
              workId: item.workId,
            );
            _emit();
          } on ApiException {
            /* The catalog remains usable when an image lookup fails. */
          }
        }),
      );
    } on ApiException catch (failure) {
      if (!_valid(generation, base)) return;
      error = failure;
    } finally {
      if (_valid(generation, base)) {
        loading = false;
        _emit();
      }
    }
  }

  bool _valid(int generation, String base) =>
      !_disposed &&
      generation == _generation &&
      services.settings.baseUrl == base;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void changeSource() {
    _generation++;
    _rich.clear();
    feed = null;
    unawaited(refresh());
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
