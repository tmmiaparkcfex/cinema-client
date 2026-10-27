import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class QuarkAccountStore {
  const QuarkAccountStore({
    this._storage = const FlutterSecureStorage(),
  });

  static const _cookieKey = 'quark_session_cookie_v1';
  final FlutterSecureStorage _storage;

  Future<String?> readCookie() async {
    final value = await _storage.read(key: _cookieKey);
    if (value == null || !value.contains('=')) return null;
    return value;
  }

  Future<void> saveCookie(String cookie) async {
    if (cookie.trim().isEmpty || cookie.contains('\n')) {
      throw const FormatException('invalid cookie');
    }
    await _storage.write(key: _cookieKey, value: cookie);
  }

  Future<void> clear() => _storage.delete(key: _cookieKey);

  Future<bool> hasCookie() async => (await readCookie()) != null;
}
