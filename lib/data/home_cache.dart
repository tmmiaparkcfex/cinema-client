import 'dart:convert';
import 'dart:io';

import '../core/app_models.dart';
import '../core/app_settings.dart';

class HomeCache {
  HomeCache(this.directory);

  final Directory directory;

  File _fileFor(String baseUrl) {
    final key = base64Url
        .encode(utf8.encode(baseUrl))
        .replaceAll('=', '')
        .replaceAll('-', '_')
        .replaceAll('+', '-');
    return File('${directory.path}/home_$key.json');
  }

  Future<HomeFeed?> read(AppSettings settings) async {
    try {
      final file = _fileFor(settings.baseUrl);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic> || decoded['base'] != settings.baseUrl) {
        return null;
      }
      final data = decoded['data'];
      if (data is! Map<String, dynamic>) return null;
      return HomeFeed.fromJson(data, fromCache: true);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(AppSettings settings, HomeFeed feed) async {
    try {
      await directory.create(recursive: true);
      final file = _fileFor(settings.baseUrl);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        jsonEncode({
          'base': settings.baseUrl,
          'savedAt': DateTime.now().toIso8601String(),
          'data': feed.toCacheJson(),
        }),
        flush: true,
      );
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
    } catch (_) {
      // The network remains the source of truth; cache failures are non-fatal.
    }
  }
}
