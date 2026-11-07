import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_models.dart';

enum ShelfStatus { want, watching }

class ShelfTitle {
  const ShelfTitle(this.item, this.status);
  final VodItem item;
  final ShelfStatus status;
}

class RexStore extends ChangeNotifier {
  RexStore(this.preferences) {
    _read();
  }
  final SharedPreferences preferences;
  final Map<String, ShelfTitle> shelf = {};
  final Map<String, VodItem> favorites = {};
  final Map<String, VodItem> recent = {};
  final Map<String, Set<int>> _episodes = {};
  final Map<String, DateTime> _watchedDates = {};
  final Map<String, bool> modules = {
    'calendar': true,
    'stats': true,
    'history': true,
    'watch': true,
  };
  bool onboarded = false;
  Future<void> _pending = Future.value();

  bool isFavorite(VodItem item) => favorites.containsKey(item.identityKey);
  ShelfStatus? status(VodItem item) => shelf[item.identityKey]?.status;
  Set<int> episodes(VodItem item, int season) =>
      Set.of(_episodes['${item.identityKey}/$season'] ?? {});
  int get watchedEpisodeCount =>
      _episodes.values.fold(0, (n, v) => n + v.length);
  List<VodItem> get recentItems => recent.values.toList().reversed.toList();

  Future<void> finishOnboarding() {
    onboarded = true;
    return _save();
  }

  Future<void> toggleFavorite(VodItem item) {
    if (isFavorite(item)) {
      favorites.remove(item.identityKey);
    } else {
      favorites[item.identityKey] = item;
    }
    return _save();
  }

  Future<void> setStatus(VodItem item, ShelfStatus? value) {
    if (value == null) {
      shelf.remove(item.identityKey);
    } else {
      shelf[item.identityKey] = ShelfTitle(item, value);
    }
    return _save();
  }

  Future<void> recordOpen(VodItem item) {
    recent.remove(item.identityKey);
    recent[item.identityKey] = item;
    while (recent.length > 12) {
      recent.remove(recent.keys.first);
    }
    return _save();
  }

  Future<void> clearRecent() {
    recent.clear();
    return _save();
  }

  Future<void> setEpisodes(VodItem item, int season, Set<int> values) {
    final key = '${item.identityKey}/$season';
    final previous = _episodes[key] ?? {};
    for (final episode in values.difference(previous)) {
      _watchedDates['$key/$episode'] = DateTime.now();
    }
    for (final episode in previous.difference(values)) {
      _watchedDates.remove('$key/$episode');
    }
    _episodes[key] = Set.of(values.where((v) => v > 0));
    return _save();
  }

  int episodesIn(DateTime start, DateTime end) => _watchedDates.values
      .where((v) => !v.isBefore(start) && v.isBefore(end))
      .length;
  Future<void> toggleModule(String key) {
    modules[key] = !(modules[key] ?? true);
    return _save();
  }

  Future<void> _save() {
    final snapshot = jsonEncode({
      'version': 1,
      'onboarded': onboarded,
      'shelf': shelf.values
          .map((v) => {'item': v.item.toCacheJson(), 'status': v.status.name})
          .toList(),
      'favorites': favorites.values.map((v) => v.toCacheJson()).toList(),
      'recent': recent.values.map((v) => v.toCacheJson()).toList(),
      'episodes': _episodes.map((k, v) => MapEntry(k, v.toList()..sort())),
      'dates': _watchedDates.map((k, v) => MapEntry(k, v.toIso8601String())),
      'modules': modules,
    });
    notifyListeners();
    _pending = _pending.catchError((Object _) {}).then((_) async {
      await preferences.setString('rex_state_v1', snapshot);
    });
    return _pending;
  }

  void _read() {
    try {
      final raw = preferences.getString('rex_state_v1');
      if (raw == null) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['version'] != 1) return;
      onboarded = json['onboarded'] == true;
      for (final row in (json['shelf'] as List? ?? [])) {
        final item = VodItem.fromCacheJson(
          Map<String, dynamic>.from(row['item'] as Map),
        );
        shelf[item.identityKey] = ShelfTitle(
          item,
          row['status'] == 'watching' ? ShelfStatus.watching : ShelfStatus.want,
        );
      }
      for (final field in ['favorites', 'recent']) {
        final target = field == 'favorites' ? favorites : recent;
        for (final row in (json[field] as List? ?? [])) {
          final item = VodItem.fromCacheJson(
            Map<String, dynamic>.from(row as Map),
          );
          if (item.key.isNotEmpty) target[item.identityKey] = item;
        }
      }
      for (final row in (json['episodes'] as Map? ?? {}).entries) {
        _episodes[row.key as String] = (row.value as List)
            .whereType<int>()
            .where((v) => v > 0)
            .toSet();
      }
      for (final row in (json['dates'] as Map? ?? {}).entries) {
        final date = DateTime.tryParse(row.value.toString());
        if (date != null) _watchedDates[row.key as String] = date;
      }
      for (final row in (json['modules'] as Map? ?? {}).entries) {
        if (modules.containsKey(row.key)) {
          modules[row.key as String] = row.value == true;
        }
      }
    } catch (_) {
      /* Preserve startup when one saved snapshot is malformed. */
    }
  }
}
