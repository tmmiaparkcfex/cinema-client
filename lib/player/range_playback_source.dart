import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Keeps Quark CDN requests bounded while mpv retains normal seekable HTTP.
/// All upstream traffic and account headers stay on the viewer's device.
class RangePlaybackSource {
  RangePlaybackSource._(this._uri, this._headers, this._length, this._server) {
    _client
      ..autoUncompress = false
      ..connectionTimeout = const Duration(seconds: 12)
      ..maxConnectionsPerHost = 2;
    _server.autoCompress = false;
    _server.listen((request) => unawaited(_serve(request)));
  }

  static const _partSize = 1024 * 1024;
  static const _window = 2;
  final Uri _uri;
  final Map<String, String> _headers;
  final int _length;
  final HttpServer _server;
  final HttpClient _client = HttpClient();
  final String _token = List.generate(
    16,
    (_) => Random.secure().nextInt(256),
  ).map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  bool _closed = false;
  bool _paused = false;
  Completer<void>? _resume;

  /// Finish at most the current bounded parts, then stop requesting bytes while
  /// the viewer pauses or backgrounds the app. No polling timer is needed.
  void setPaused(bool paused) {
    if (_closed || _paused == paused) return;
    _paused = paused;
    if (paused) {
      _resume = Completer<void>();
    } else {
      _resume?.complete();
      _resume = null;
    }
  }

  Future<void> _waitForResume() async {
    while (_paused && !_closed) {
      await _resume!.future;
    }
  }

  static Future<RangePlaybackSource> open({
    required Uri uri,
    required Map<String, String> headers,
    required int length,
  }) async {
    if (length <= 0) throw ArgumentError.value(length, 'length');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return RangePlaybackSource._(uri, Map.of(headers), length, server);
  }

  Uri get uri => Uri.parse('http://127.0.0.1:${_server.port}/$_token');

  Future<Uint8List> _part(
    int start,
    int end,
    List<HttpClientRequest> active,
  ) async {
    var target = _uri;
    var headers = Map<String, String>.of(_headers);
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (_closed) throw const HttpException('Playback source closed');
      final request = await _client.getUrl(target);
      active.add(request);
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final location = response.headers.value(HttpHeaders.locationHeader);
      if ([301, 302, 303, 307, 308].contains(response.statusCode) &&
          location != null) {
        request.abort();
        active.remove(request);
        final next = target.resolve(location);
        if (next.scheme != 'https' &&
            (target.scheme == 'https' || next.scheme != 'http')) {
          throw const HttpException('Invalid CDN redirect');
        }
        if (next.origin != target.origin) {
          headers.removeWhere(
            (name, _) =>
                ['cookie', 'authorization'].contains(name.toLowerCase()),
          );
        }
        target = next;
        continue;
      }
      final contentRange = response.headers.value(
        HttpHeaders.contentRangeHeader,
      );
      if (response.statusCode != HttpStatus.partialContent ||
          contentRange != 'bytes $start-$end/$_length') {
        request.abort();
        active.remove(request);
        throw const HttpException('CDN byte range mismatch');
      }
      final bytes = BytesBuilder(copy: false);
      try {
        await (() async {
          await for (final chunk in response) {
            bytes.add(chunk);
            if (bytes.length > end - start + 1) {
              throw const HttpException('CDN range overflow');
            }
          }
        })().timeout(const Duration(seconds: 15));
        if (bytes.length != end - start + 1) {
          throw const HttpException('CDN range truncated');
        }
        return bytes.takeBytes();
      } finally {
        request.abort();
        active.remove(request);
      }
    }
    throw const HttpException('Too many CDN redirects');
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    final active = <HttpClientRequest>[];
    var disconnected = false;
    unawaited(
      response.done.then<void>(
        (_) {
          disconnected = true;
        },
        onError: (Object _) {
          disconnected = true;
          for (final upstream in List.of(active)) {
            upstream.abort();
          }
        },
      ),
    );
    try {
      if (_closed || request.uri.path != '/$_token') {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      if (!['GET', 'HEAD'].contains(request.method)) {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      var start = 0;
      var end = _length - 1;
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
        if (match == null || (match[1]!.isEmpty && match[2]!.isEmpty)) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          return;
        }
        if (match[1]!.isEmpty) {
          start = max(0, _length - int.parse(match[2]!));
        } else {
          start = int.parse(match[1]!);
          if (match[2]!.isNotEmpty) end = min(end, int.parse(match[2]!));
        }
        if (start > end || start >= _length) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes */$_length',
          );
          return;
        }
      }
      response.statusCode = range == null
          ? HttpStatus.ok
          : HttpStatus.partialContent;
      response.headers
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..set(HttpHeaders.cacheControlHeader, 'no-store')
        ..contentType = ContentType.binary
        ..contentLength = end - start + 1;
      if (range != null) {
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$_length',
        );
      }
      if (request.method == 'HEAD') return;
      final pending = <int, Future<Uint8List>>{};
      var next = start;
      void fill() {
        while (!disconnected &&
            !_closed &&
            pending.length < _window &&
            next <= end) {
          final offset = next;
          final future = _part(
            offset,
            min(end, offset + _partSize - 1),
            active,
          );
          // A player seek can discard prefetched chunks. Always observe errors.
          unawaited(future.then<void>((_) {}, onError: (Object _) {}));
          pending[offset] = future;
          next += _partSize;
        }
      }

      await _waitForResume();
      fill();
      for (
        var offset = start;
        offset <= end && !disconnected && !_closed;
        offset += _partSize
      ) {
        await _waitForResume();
        if (_closed || disconnected) break;
        final bytes = await pending.remove(offset)!;
        await _waitForResume();
        if (_closed || disconnected) break;
        response.add(bytes);
        await response.flush();
        fill();
      }
    } catch (_) {
      // Stop this HTTP stream; the player reports the interruption and can
      // refresh the lease. Never return an error body as video bytes.
      try {
        (await response.detachSocket()).destroy();
      } catch (_) {}
    } finally {
      for (final upstream in List.of(active)) {
        upstream.abort();
      }
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _resume?.complete();
    _resume = null;
    _client.close(force: true);
    await _server.close(force: true);
  }
}
