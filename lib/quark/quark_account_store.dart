import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class QuarkAccountStore {
  const QuarkAccountStore({this._storage = const FlutterSecureStorage()});

  static const _cookieKey = 'quark_session_cookie_v1';
  final FlutterSecureStorage _storage;

  Future<String?> readCookie() async {
    return (await _readSession())?.cookie;
  }

  Future<String?> readSessionId() async => (await _readSession())?.scope;

  Future<({String cookie, String scope})?> _readSession() async {
    final value = await _storage.read(key: _cookieKey);
    if (value == null) return null;
    if (value.startsWith('{')) {
      Object? json;
      try {
        json = jsonDecode(value);
      } on FormatException {
        return null;
      }
      if (json is! Map ||
          json['cookie'] is! String ||
          json['scope'] is! String) {
        return null;
      }
      final cookie = json['cookie'] as String;
      final scope = json['scope'] as String;
      return cookie.contains('=') && scope.isNotEmpty
          ? (cookie: cookie, scope: scope)
          : null;
    }
    // Accept the older raw-cookie value until the next session write.
    if (!value.contains('=')) return null;
    return (
      cookie: value,
      scope: sha256.convert(utf8.encode(value)).toString(),
    );
  }

  Future<void> saveCookie(String cookie, {bool preserveSession = false}) async {
    if (!cookie.contains('=') ||
        cookie.contains('\n') ||
        cookie.contains('\r')) {
      throw const FormatException('invalid cookie');
    }
    final oldScope = preserveSession ? await readSessionId() : null;
    final random = Random.secure();
    final scope =
        oldScope ??
        List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
    await _storage.write(
      key: _cookieKey,
      value: jsonEncode({'cookie': cookie, 'scope': scope}),
    );
  }

  Future<void> clear() => _storage.delete(key: _cookieKey);

  Future<bool> hasCookie() async => (await readCookie()) != null;
}
