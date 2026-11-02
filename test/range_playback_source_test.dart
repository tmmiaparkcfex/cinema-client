import 'dart:io';

import 'package:cinema_client/player/range_playback_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  late HttpServer upstream;
  late RangePlaybackSource source;
  final ranges = <String>[];
  bool wrongRange = false;
  Uri? redirect;
  final bytes = List.generate(5 * 1024 * 1024 + 13, (n) => n % 251);

  setUp(() async {
    ranges.clear();
    wrongRange = false;
    redirect = null;
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      if (redirect != null) {
        request.response.statusCode = 302;
        request.response.headers.set('location', redirect.toString());
        await request.response.close();
        return;
      }
      final range = request.headers.value('range')!;
      ranges.add(range);
      final match = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(range)!;
      final start = int.parse(match[1]!);
      final end = int.parse(match[2]!);
      request.response
        ..statusCode = 206
        ..headers.set(
          'content-range',
          'bytes ${wrongRange ? start + 1 : start}-$end/${bytes.length}',
        )
        ..contentLength = end - start + 1
        ..add(bytes.sublist(start, end + 1));
      await request.response.close();
    });
    source = await RangePlaybackSource.open(
      uri: Uri.parse('http://127.0.0.1:${upstream.port}/media'),
      headers: {},
      length: bytes.length,
    );
  });
  tearDown(() async {
    await source.close();
    await upstream.close(force: true);
  });

  test(
    'streams the complete original file through bounded upstream ranges',
    () async {
      final response = await http.get(source.uri);
      expect(response.statusCode, 200);
      expect(response.bodyBytes, bytes);
      expect(ranges.length, 6);
      expect(
        ranges.every((range) => RegExp(r'^bytes=\d+-\d+$').hasMatch(range)),
        true,
      );
      expect(ranges, contains('bytes=5242880-5242892'));
    },
  );

  test('preserves random seek and suffix ranges byte for byte', () async {
    var response = await http.get(
      source.uri,
      headers: {'Range': 'bytes=12345-2123456'},
    );
    expect(response.statusCode, 206);
    expect(
      response.headers['content-range'],
      'bytes 12345-2123456/${bytes.length}',
    );
    expect(response.bodyBytes, bytes.sublist(12345, 2123457));
    response = await http.get(source.uri, headers: {'Range': 'bytes=-31'});
    expect(response.bodyBytes, bytes.sublist(bytes.length - 31));
  });

  test('HEAD and invalid ranges never fetch upstream video bytes', () async {
    final response = await http.head(source.uri);
    expect(response.headers['content-length'], '${bytes.length}');
    expect(ranges, isEmpty);
    for (final range in [
      'bytes=9000000-',
      'bytes=50-12',
      'bytes=-',
      'bytes=1-2,4-5',
      'bytes=-0',
    ]) {
      final rejected = await http.get(source.uri, headers: {'Range': range});
      expect(rejected.statusCode, 416, reason: range);
    }
    expect(ranges, isEmpty);
  });

  test(
    'unpredictable local path is required and closing releases the listener',
    () async {
      final missing = await http.get(source.uri.replace(path: '/media'));
      expect(missing.statusCode, 404);
      expect(ranges, isEmpty);
      final uri = source.uri;
      await source.close();
      await expectLater(http.get(uri), throwsA(isA<http.ClientException>()));
    },
  );

  test(
    'rejects a mismatched CDN range instead of returning corrupted video',
    () async {
      wrongRange = true;
      await expectLater(
        http.get(source.uri, headers: {'Range': 'bytes=0-31'}),
        throwsA(isA<http.ClientException>()),
      );
    },
  );

  test(
    'CDN redirects never forward account credentials to another origin',
    () async {
      final destination = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => destination.close(force: true));
      final receivedCookies = <String?>[];
      destination.listen((request) async {
        receivedCookies.add(request.headers.value('cookie'));
        request.response
          ..statusCode = 206
          ..headers.set('content-range', 'bytes 0-31/${bytes.length}')
          ..contentLength = 32
          ..add(bytes.sublist(0, 32));
        await request.response.close();
      });
      redirect = Uri.parse('http://127.0.0.1:${destination.port}/media');
      await source.close();
      source = await RangePlaybackSource.open(
        uri: Uri.parse('http://127.0.0.1:${upstream.port}/media'),
        headers: {'Cookie': 'synthetic-account', 'Authorization': 'synthetic'},
        length: bytes.length,
      );
      final response = await http.get(
        source.uri,
        headers: {'Range': 'bytes=0-31'},
      );
      expect(response.bodyBytes, bytes.sublist(0, 32));
      expect(receivedCookies, [null]);
    },
  );
}
