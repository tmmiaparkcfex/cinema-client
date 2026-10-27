import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_models.dart';

class SavedTitle {
  const SavedTitle({
    required this.key,
    required this.name,
    required this.mediaType,
    required this.poster,
    required this.year,
    required this.savedAt,
  });

  final String key;
  final String name;
  final MediaKind mediaType;
  final String? poster;
  final int? year;
  final DateTime savedAt;

  VodItem toItem() => VodItem(
        key: key,
        name: name,
        mediaType: mediaType,
        poster: poster,
        year: year,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'mediaType': mediaType.name,
        'poster': poster,
        'year': year,
        'savedAt': savedAt.millisecondsSinceEpoch,
      };

  factory SavedTitle.fromJson(Map<String, dynamic> json) => SavedTitle(
        key: json['key']?.toString() ?? '',
        name: json['name']?.toString() ?? '未命名作品',
        mediaType: parseMediaKind(json['mediaType']),
        poster: json['poster']?.toString(),
        year: int.tryParse(json['year']?.toString() ?? ''),
        savedAt: DateTime.fromMillisecondsSinceEpoch(
          int.tryParse(json['savedAt']?.toString() ?? '') ?? 0,
        ),
      );
}

class PlaybackRecord {
  const PlaybackRecord({
    required this.itemKey,
    required this.name,
    required this.mediaType,
    required this.poster,
    this.season,
    this.episode,
    required this.positionMs,
    required this.durationMs,
    required this.lineGroup,
    required this.resourceId,
    required this.updatedAt,
    this.completed = false,
  });

  final String itemKey;
  final String name;
  final MediaKind mediaType;
  final String? poster;
  final int? season;
  final int? episode;
  final int positionMs;
  final int durationMs;
  final String lineGroup;
  final String resourceId;
  final DateTime updatedAt;
  final bool completed;

  int get safePositionMs => positionMs.clamp(0, durationMs > 0 ? durationMs : positionMs);
  double get progress => durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0, 1);

  VodItem toItem() => VodItem(
        key: itemKey,
        name: name,
        mediaType: mediaType,
        poster: poster,
      );

  String get episodeText {
    if (mediaType != MediaKind.tv || episode == null) return '';
    return '第$episode集';
  }

  Map<String, dynamic> toJson() => {
        'itemKey': itemKey,
        'name': name,
        'mediaType': mediaType.name,
        'poster': poster,
        'season': season,
        'episode': episode,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'lineGroup': lineGroup,
        'resourceId': resourceId,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'completed': completed,
      };

  factory PlaybackRecord.fromJson(Map<String, dynamic> json) => PlaybackRecord(
        itemKey: json['itemKey']?.toString() ?? '',
        name: json['name']?.toString() ?? '未命名作品',
        mediaType: parseMediaKind(json['mediaType']),
        poster: json['poster']?.toString(),
        season: int.tryParse(json['season']?.toString() ?? ''),
        episode: int.tryParse(json['episode']?.toString() ?? ''),
        positionMs: int.tryParse(json['positionMs']?.toString() ?? '') ?? 0,
        durationMs: int.tryParse(json['durationMs']?.toString() ?? '') ?? 0,
        lineGroup: json['lineGroup']?.toString() ?? '',
        resourceId: json['resourceId']?.toString() ?? '',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          int.tryParse(json['updatedAt']?.toString() ?? '') ?? 0,
        ),
        completed: json['completed'] == true,
      );
}

class LocalStore extends ChangeNotifier {
  LocalStore._(this._prefs) {
    _load();
  }

  static const _historyKey = 'watch_records_v1';
  static const _favoritesKey = 'favorites_v1';
  static const int _historyLimit = 100;

  final SharedPreferences _prefs;
  final Map<String, SavedTitle> _favorites = {};
  final Map<String, PlaybackRecord> _history = {};

  static LocalStore load(SharedPreferences prefs) => LocalStore._(prefs);

  List<PlaybackRecord> get history {
    final values = _history.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return values;
  }

  List<SavedTitle> get favorites {
    final values = _favorites.values.toList()
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return values;
  }

  PlaybackRecord? recordFor(String itemKey) => _history[itemKey];

  bool isFavorite(String itemKey) => _favorites.containsKey(itemKey);

  Future<void> toggleFavorite(VodItem item) async {
    if (_favorites.remove(item.key) == null) {
      _favorites[item.key] = SavedTitle(
        key: item.key,
        name: item.name,
        mediaType: item.mediaType,
        poster: item.poster,
        year: item.year,
        savedAt: DateTime.now(),
      );
    }
    await _persistFavorites();
    notifyListeners();
  }

  Future<void> saveProgress({
    required VodItem item,
    required MediaResource resource,
    required Duration position,
    required Duration duration,
    required String lineGroup,
    bool completed = false,
  }) async {
    if (item.key.isEmpty || resource.id.isEmpty) return;
    _history[item.key] = PlaybackRecord(
      itemKey: item.key,
      name: item.name,
      mediaType: item.mediaType,
      poster: item.poster,
      season: resource.season,
      episode: resource.episode,
      positionMs: position.inMilliseconds,
      durationMs: duration.inMilliseconds,
      lineGroup: lineGroup,
      resourceId: resource.id,
      updatedAt: DateTime.now(),
      completed: completed,
    );
    if (_history.length > _historyLimit) {
      final oldest = history.last;
      _history.remove(oldest.itemKey);
    }
    await _persistHistory();
    notifyListeners();
  }

  Future<void> removeHistoryRecord(String itemKey) async {
    if (_history.remove(itemKey) == null) return;
    await _persistHistory();
    notifyListeners();
  }

  Future<void> clearHistory() async {
    _history.clear();
    await _persistHistory();
    notifyListeners();
  }

  Future<void> removeFavorite(String key) async {
    if (_favorites.remove(key) == null) return;
    await _persistFavorites();
    notifyListeners();
  }

  void _load() {
    for (final raw in _prefs.getStringList(_favoritesKey) ?? const <String>[]) {
      try {
        final value = jsonDecode(raw);
        if (value is Map<String, dynamic>) {
          final item = SavedTitle.fromJson(value);
          if (item.key.isNotEmpty) _favorites[item.key] = item;
        }
      } catch (_) {
        // A corrupt local row must not prevent startup.
      }
    }
    for (final raw in _prefs.getStringList(_historyKey) ?? const <String>[]) {
      try {
        final value = jsonDecode(raw);
        if (value is Map<String, dynamic>) {
          final record = PlaybackRecord.fromJson(value);
          if (record.itemKey.isNotEmpty) _history[record.itemKey] = record;
        }
      } catch (_) {
        // Ignore malformed local rows.
      }
    }
  }

  Future<void> _persistFavorites() async {
    await _prefs.setStringList(
      _favoritesKey,
      _favorites.values.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  Future<void> _persistHistory() async {
    await _prefs.setStringList(
      _historyKey,
      _history.values.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }
}
