import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String defaultVodApiBase = String.fromEnvironment(
  'VOD_API_BASE',
  defaultValue: 'http://192.168.1.4:8765',
);

class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs, this._baseUrl);

  static const _baseKey = 'vod_api_base';

  final SharedPreferences _prefs;
  String _baseUrl;

  String get baseUrl => _baseUrl;

  static AppSettings load(SharedPreferences prefs) {
    final stored = prefs.getString(_baseKey)?.trim();
    return AppSettings._(
      prefs,
      normalizeApiBase(stored == null || stored.isEmpty ? defaultVodApiBase : stored) ??
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
