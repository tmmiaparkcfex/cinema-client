import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_log.dart';
import '../core/app_models.dart';
import '../player/range_playback_source.dart';
import '../quark/quark_playback_service.dart';

enum DownloadState { queued, preparing, downloading, paused, complete, failed }

class DownloadJob {
  DownloadJob({
    required this.item,
    required this.resource,
    required this.label,
    this.state = DownloadState.queued,
    this.received = 0,
  });
  final VodItem item;
  final MediaResource resource;
  final String label;
  DownloadState state;
  int received;
  String? error;
  String get id => resource.id;
  double get progress =>
      resource.sizeBytes <= 0 ? 0 : (received / resource.sizeBytes).clamp(0, 1);
  String get stateLabel => switch (state) {
    DownloadState.queued => '等待下载',
    DownloadState.preparing => '正在准备',
    DownloadState.downloading => '正在下载',
    DownloadState.paused => '已暂停',
    DownloadState.complete => '已完成',
    DownloadState.failed => '下载失败',
  };
  Map<String, dynamic> toJson() => {
    'item': item.toCacheJson(),
    'resource': resource.toJson(),
    'label': label,
    'state': state.name,
    'received': received,
  };
}

/// A temporary account lease; no CDN URL or credential is persisted.
class DownloadConnection {
  DownloadConnection({
    required this.uri,
    required this.headers,
    required this.release,
  });
  final Uri uri;
  final Map<String, String> headers;
  final Future<void> Function() release;
}

class DownloadManager extends ChangeNotifier with WidgetsBindingObserver {
  DownloadManager({
    required this.prefs,
    required this.directory,
    required this.connect,
  }) {
    WidgetsBinding.instance.addObserver(this);
  }

  final SharedPreferences prefs;
  final Directory directory;
  final Future<DownloadConnection> Function(
    MediaResource,
    QuarkPlaybackCancellation,
  )
  connect;
  static const _key = 'cinema_downloads_v1';
  final _jobs = <DownloadJob>[];
  List<DownloadJob> get jobs => List.unmodifiable(_jobs);
  DownloadJob? _active;
  Future<void>? _runner;
  QuarkPlaybackCancellation? _cancellation;
  HttpClient? _client;
  RangePlaybackSource? _source;
  bool _foreground = true;
  bool _closed = false;

  // Paths derive solely from a hash; server file names never become local paths.
  File _file(DownloadJob job, {bool partial = false}) => File(
    '${directory.path}/${sha256.convert(utf8.encode(job.id))}.media${partial ? '.part' : ''}',
  );
  String localPath(DownloadJob job) => _file(job).path;

  Future<void> restore() async {
    await directory.create(recursive: true);
    try {
      final rows = jsonDecode(prefs.getString(_key) ?? '[]') as List;
      for (final value in rows) {
        final row = Map<String, dynamic>.from(value as Map);
        final job = DownloadJob(
          item: VodItem.fromCacheJson(
            Map<String, dynamic>.from(row['item'] as Map),
          ),
          resource: MediaResource.fromJson(
            Map<String, dynamic>.from(row['resource'] as Map),
          ),
          label: row['label'] as String? ?? '正片',
          state: DownloadState.paused,
        );
        if (job.id.isEmpty ||
            job.resource.sizeBytes <= 0 ||
            _jobs.any((e) => e.id == job.id)) {
          continue;
        }
        final complete = _file(job);
        final part = _file(job, partial: true);
        if (await complete.exists() &&
            await complete.length() == job.resource.sizeBytes) {
          job.state = DownloadState.complete;
          job.received = job.resource.sizeBytes;
        } else if (await part.exists()) {
          job.received = await part.length();
        }
        _jobs.add(job);
      }
    } catch (error) {
      AppLog.error('downloads-restore', error.runtimeType);
    }
    notifyListeners();
  }

  Future<void> enqueue(
    VodItem item,
    MediaResource resource,
    String label,
  ) async {
    if (resource.id.isEmpty || resource.sizeBytes <= 0) {
      throw const FormatException('文件信息不完整，无法下载。');
    }
    final existing = _jobs.where((e) => e.id == resource.id).firstOrNull;
    if (existing != null) {
      if (existing.state != DownloadState.complete) await resume(existing);
      return;
    }
    _jobs.insert(0, DownloadJob(item: item, resource: resource, label: label));
    await _save();
    _changed();
    _pump();
  }

  Future<void> resume(DownloadJob job) async {
    if (job.state == DownloadState.complete || identical(job, _active)) return;
    job.state = DownloadState.queued;
    job.error = null;
    await _save();
    _changed();
    _pump();
  }

  Future<void> pause(DownloadJob job) async {
    if (job.state == DownloadState.complete) return;
    job.state = DownloadState.paused;
    if (identical(job, _active)) {
      _cancellation?.cancel();
      _client?.close(force: true);
      await _source?.close();
      await _runner;
    }
    await _save();
    _changed();
  }

  Future<void> pauseAll() async {
    for (final job in _jobs) {
      if ([
        DownloadState.queued,
        DownloadState.preparing,
        DownloadState.downloading,
      ].contains(job.state)) {
        job.state = DownloadState.paused;
      }
    }
    _cancellation?.cancel();
    _client?.close(force: true);
    await _source?.close();
    await _runner;
    await _save();
    _changed();
  }

  Future<void> remove(DownloadJob job) async {
    await pause(job);
    for (final file in [_file(job), _file(job, partial: true)]) {
      if (await file.exists()) await file.delete();
    }
    _jobs.remove(job);
    await _save();
    _changed();
  }

  void _pump() {
    if (_runner != null || !_foreground || _closed) return;
    final job = _jobs.where((e) => e.state == DownloadState.queued).firstOrNull;
    if (job == null) return;
    _active = job;
    _runner = _run(job).whenComplete(() {
      _active = null;
      _runner = null;
      _pump();
    });
  }

  Future<void> _run(DownloadJob job) async {
    DownloadConnection? connection;
    RandomAccessFile? output;
    final cancellation = QuarkPlaybackCancellation();
    _cancellation = cancellation;
    try {
      job.state = DownloadState.preparing;
      _changed();
      await directory.create(recursive: true);
      final part = _file(job, partial: true);
      var offset = await part.exists() ? await part.length() : 0;
      if (offset > job.resource.sizeBytes) {
        await part.delete();
        offset = 0;
      }
      if (offset < job.resource.sizeBytes) {
        connection = await connect(job.resource, cancellation);
        cancellation.throwIfCancelled();
        _source = await RangePlaybackSource.open(
          uri: connection.uri,
          headers: connection.headers,
          length: job.resource.sizeBytes,
        );
        cancellation.throwIfCancelled();
        _client = HttpClient();
        final request = await _client!.getUrl(_source!.uri);
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
        if (response.statusCode != 206 ||
            response.headers.value('content-range') !=
                'bytes $offset-${job.resource.sizeBytes - 1}/${job.resource.sizeBytes}') {
          throw const HttpException('Download range mismatch');
        }
        output = await part.open(mode: FileMode.append);
        job.received = offset;
        job.state = DownloadState.downloading;
        _changed();
        final clock = Stopwatch()..start();
        var lastPaint = 0;
        await for (final bytes in response.timeout(
          const Duration(seconds: 30),
        )) {
          cancellation.throwIfCancelled();
          if (job.received + bytes.length > job.resource.sizeBytes) {
            throw const HttpException('Download overflow');
          }
          await output.writeFrom(bytes);
          job.received += bytes.length;
          if (clock.elapsedMilliseconds - lastPaint >= 500) {
            lastPaint = clock.elapsedMilliseconds;
            _changed();
          }
        }
        await output.flush();
        await output.close();
        output = null;
      }
      cancellation.throwIfCancelled();
      if (await part.length() != job.resource.sizeBytes) {
        throw const HttpException('Download truncated');
      }
      await part.rename(_file(job).path);
      job.received = job.resource.sizeBytes;
      job.state = DownloadState.complete;
    } catch (error) {
      if (cancellation.isCancelled) {
        job.state = DownloadState.paused;
      } else {
        job.state = DownloadState.failed;
        job.error = error is QuarkException
            ? error.userMessage
            : error is FileSystemException
            ? '无法写入文件，请检查手机剩余空间。'
            : '网络或文件下载失败，可从已保存的位置重试。';
        AppLog.error(
          'download',
          error is HttpException ? error.message : error.runtimeType,
        );
      }
    } finally {
      try {
        await output?.close();
      } catch (error) {
        AppLog.error('download-file-close', error.runtimeType);
      }
      _client?.close(force: true);
      _client = null;
      await _source?.close();
      _source = null;
      try {
        await connection?.release();
      } catch (error) {
        AppLog.error('download-release', error.runtimeType);
      }
      _cancellation = null;
      await _save();
      _changed();
    }
  }

  Future<void> _save() async {
    try {
      await prefs.setString(
        _key,
        jsonEncode(_jobs.map((e) => e.toJson()).toList()),
      );
    } catch (error) {
      AppLog.error('download-save', error.runtimeType);
    }
  }

  void _changed() {
    if (!_closed) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) unawaited(pauseAll());
    // Returning to the foreground does not silently restart large transfers.
  }

  @override
  void dispose() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(pauseAll());
    super.dispose();
  }
}
