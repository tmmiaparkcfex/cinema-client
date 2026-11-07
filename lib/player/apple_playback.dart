import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

class ApplePlayback {
  ApplePlayback(this.onEvent, {required this.usesAether});
  final ValueChanged<Map<Object?, Object?>> onEvent;
  final bool usesAether;
  MethodChannel? _channel;
  final _attached = Completer<void>();
  bool _closed = false;
  bool pip = false;
  Tracks tracks = const Tracks();
  Track track = const Track();
  List<(int, String)> chapters = [];
  _AppleFileRelay? _relay;

  static bool canOpen(String name) =>
      defaultTargetPlatform == TargetPlatform.iOS &&
      RegExp(r'\.(mp4|mov|m4v|mkv)$', caseSensitive: false).hasMatch(name);

  Widget get view => UiKitView(
    key: ObjectKey(this),
    viewType: usesAether ? 'cinema/aether-player' : 'cinema/apple-player',
    onPlatformViewCreated: (id) {
      if (_closed) return;
      final channel = MethodChannel('cinema/apple-player/$id');
      _channel = channel;
      channel.setMethodCallHandler((call) async {
        if (call.method != 'state' || call.arguments is! Map) return;
        final event = Map<Object?, Object?>.from(call.arguments as Map);
        pip = event['pip'] == true;
        chapters = [
          for (final item
              in (event['chapters'] as List? ?? []).whereType<Map>())
            if (item['position'] is int)
              (item['position'] as int, item['title']?.toString() ?? '片段'),
        ];
        final audio = <AudioTrack>[
          for (final item in (event['audio'] as List? ?? []).whereType<Map>())
            AudioTrack(
              item['id'].toString(),
              item['name'] as String?,
              item['language'] as String?,
              codec: item['codec'] as String?,
            ),
        ];
        final subtitles = <SubtitleTrack>[
          for (final item
              in (event['subtitles'] as List? ?? []).whereType<Map>())
            SubtitleTrack(
              item['id'].toString(),
              item['name'] as String?,
              item['language'] as String?,
              codec: item['codec'] as String?,
            ),
        ];
        tracks = Tracks(audio: audio, subtitle: subtitles);
        track = Track(
          audio:
              audio.where((v) => v.id == event['audioId']).firstOrNull ??
              AudioTrack.auto(),
          subtitle:
              subtitles.where((v) => v.id == event['subtitleId']).firstOrNull ??
              SubtitleTrack.no(),
        );
        onEvent(event);
      });
      if (!_attached.isCompleted) _attached.complete();
    },
  );

  Future<void> open(
    Uri upstream,
    Map<String, String> headers,
    String fileName,
    Duration position,
  ) async {
    final relay = await _AppleFileRelay.start(upstream, headers, fileName);
    if (_closed) {
      await relay.close();
      throw StateError('Apple playback closed');
    }
    _relay = relay;
    await _attached.future.timeout(const Duration(seconds: 4));
    if (_closed) throw StateError('Apple playback closed');
    await _channel!
        .invokeMethod<void>('open', {
          'url': relay.uri.toString(),
          'position': position.inMilliseconds,
        })
        .timeout(Duration(seconds: usesAether ? 25 : 18));
  }

  Future<void> send(String action, [Object? value]) async {
    if (_closed) return;
    await _channel?.invokeMethod<void>(action, value);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (!_attached.isCompleted) _attached.complete();
    final channel = _channel;
    channel?.setMethodCallHandler(null);
    try {
      await channel
          ?.invokeMethod<void>('close')
          .timeout(const Duration(seconds: 2));
    } on Object {
      // A detached platform view has already released the native player.
    } finally {
      await _relay?.close();
    }
  }
}

/// AVPlayer accepts byte ranges but does not expose per-request HTTP headers.
/// The loopback endpoint serves one resolved file and never exposes its headers.
class _AppleFileRelay {
  _AppleFileRelay(this.server, this.client, this.uri);
  final HttpServer server;
  final HttpClient client;
  final Uri uri;

  static Future<_AppleFileRelay> start(
    Uri upstream,
    Map<String, String> headers,
    String fileName,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..autoUncompress = false;
    final random = Random.secure();
    final token = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final suffix = fileName.split('.').last.toLowerCase();
    final uri = Uri.parse(
      'http://127.0.0.1:${server.port}/$token/video.$suffix',
    );
    final relay = _AppleFileRelay(server, client, uri);
    server.listen((request) => relay._serve(request, upstream, headers));
    return relay;
  }

  Future<void> _serve(
    HttpRequest request,
    Uri upstream,
    Map<String, String> headers,
  ) async {
    final response = request.response;
    if (request.uri.path != uri.path ||
        !{'GET', 'HEAD'}.contains(request.method)) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    try {
      final source = await client.openUrl(request.method, upstream);
      headers.forEach((name, value) => source.headers.set(name, value));
      source.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) source.headers.set(HttpHeaders.rangeHeader, range);
      final input = await source.close().timeout(const Duration(seconds: 20));
      response.statusCode = input.statusCode;
      for (final name in [
        HttpHeaders.contentLengthHeader,
        HttpHeaders.contentRangeHeader,
        HttpHeaders.acceptRangesHeader,
        HttpHeaders.lastModifiedHeader,
        HttpHeaders.etagHeader,
      ]) {
        final value = input.headers.value(name);
        if (value != null) response.headers.set(name, value);
      }
      response.headers.set(
        HttpHeaders.contentTypeHeader,
        uri.path.endsWith('.mkv') ? 'video/x-matroska' : 'video/mp4',
      );
      if (request.method == 'GET') await response.addStream(input);
    } on Object {
      try {
        response.statusCode = HttpStatus.badGateway;
      } on StateError {
        /* Headers sent. */
      }
    } finally {
      try {
        await response.close();
      } on Object {
        /* AVPlayer canceled the range. */
      }
    }
  }

  Future<void> close() async {
    client.close(force: true);
    await server.close(force: true);
  }
}
