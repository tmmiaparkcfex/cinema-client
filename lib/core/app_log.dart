import 'dart:io';

import 'package:flutter/foundation.dart';

/// Small on-device log. It intentionally never accepts cookies, headers,
/// resource ids or playback URLs.
class AppLog {
  AppLog._();

  static File? _file;
  static const int _maxBytes = 1024 * 1024;

  static Future<void> initialize(Directory supportDirectory) async {
    try {
      final directory = Directory('${supportDirectory.path}/logs');
      await directory.create(recursive: true);
      final file = File('${directory.path}/cinema-client.log');
      if (await file.exists() && await file.length() > _maxBytes) {
        final previous = File('${directory.path}/cinema-client.previous.log');
        if (await previous.exists()) await previous.delete();
        await file.rename(previous.path);
      }
      _file = file;
    } catch (_) {
      // Logging must never prevent the app from starting.
      _file = null;
    }
  }

  static String get filePath => _file?.path ?? '';

  static void info(String tag, String message) {
    _write('INFO', tag, message);
  }

  static void error(String tag, Object error) {
    _write('ERROR', tag, _safeMessage(error.toString()));
  }

  static void _write(String level, String tag, String message) {
    final line = '${DateTime.now().toIso8601String()} $level $tag ${_safeMessage(message)}';
    if (kDebugMode) debugPrint(line);
    final file = _file;
    if (file == null) return;
    try {
      // A single short line per event; truncation protects the on-device log.
      file.writeAsStringSync(
        line.length > 1200 ? '${line.substring(0, 1200)}…\n' : '$line\n',
        mode: FileMode.append,
        flush: false,
      );
    } catch (_) {
      // Best effort only.
    }
  }

  static String _safeMessage(String value) {
    return value
        .replaceAll(RegExp(r'https?://\S+'), '[url]')
        .replaceAll(
          RegExp(r'cookie[=:]\s*\S+', caseSensitive: false),
          'cookie=[redacted]',
        )
        .replaceAll(
          RegExp(r'(token|password)=[^&\s]+', caseSensitive: false),
          'credential=[redacted]',
        );
  }
}
