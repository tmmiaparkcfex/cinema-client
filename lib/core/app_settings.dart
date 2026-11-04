import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String defaultVodApiBase = String.fromEnvironment(
  'VOD_API_BASE',
  defaultValue: 'http://172.16.3.70:8790',
);

class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs, this._baseUrl);

  static const _baseKey = 'vod_api_base';

  final SharedPreferences _prefs;
  String _baseUrl;

  String get baseUrl => _baseUrl;
  double get playbackRate => _prefs.getDouble('playback_rate') ?? 1;
  bool get autoNext => _prefs.getBool('auto_next') ?? true;
  Future<void> setPlaybackRate(double value) async {
    await _prefs.setDouble('playback_rate', value);
    notifyListeners();
  }

  Future<void> setAutoNext(bool value) async {
    await _prefs.setBool('auto_next', value);
    notifyListeners();
  }

  List<String> get searchHistory =>
      _prefs.getStringList('cinema_search_history') ?? const [];

  Future<void> rememberSearch(String query) async {
    final value = query.trim();
    if (value.isEmpty) return;
    await _prefs.setStringList(
      'cinema_search_history',
      [value, ...searchHistory.where((e) => e != value)].take(12).toList(),
    );
  }

  Future<void> clearSearchHistory() async {
    await _prefs.remove('cinema_search_history');
    notifyListeners();
  }

  Future<void> removeSearch(String query) async {
    await _prefs.setStringList(
      'cinema_search_history',
      searchHistory.where((entry) => entry != query).toList(),
    );
    notifyListeners();
  }

  static AppSettings load(SharedPreferences prefs) {
    final stored = prefs.getString(_baseKey)?.trim();
    return AppSettings._(
      prefs,
      normalizeApiBase(
            stored == null || stored.isEmpty ? defaultVodApiBase : stored,
          ) ??
          defaultVodApiBase,
    );
  }

  Future<bool> updateBaseUrl(String raw) async {
    final value = normalizeApiBase(raw);
    if (value == null) return false;
    if (value == _baseUrl) return true;
    await _prefs.setString(_baseKey, value);
    _baseUrl = value;
    notifyListeners();
    return true;
  }

  static String? normalizeApiBase(String raw) {
    final value = raw.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    return value;
  }
}
