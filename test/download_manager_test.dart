import 'dart:async';
import 'dart:io';

import 'package:cinema_client/core/app_models.dart';
import 'package:cinema_client/data/download_manager.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> waitFor(DownloadManager manager, bool Function() done) async {
  if (done()) return;
  final completed = Completer<void>();
  void changed() {
    if (done() && !completed.isCompleted) completed.complete();
  }

  manager.addListener(changed);
  try {
    await completed.future.timeout(const Duration(seconds: 8));
  } finally {
    manager.removeListener(changed);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const item = VodItem(
    key: 'test-film',
    name: '测试影片',
    mediaType: MediaKind.movie,
  );
  final bytes = List.generate(3 * 1024 * 1024 + 17, (n) => n % 251);
  late Directory directory;
  late SharedPreferences prefs;
  late HttpServer server;
  final ranges = <int>[];
  var released = 0;
  late DownloadManager manager;

  MediaResource resource(String id) => MediaResource.fromJson({
    'id': id,
    'share': {'id': 'share'},
    'file': {'id': 'fid', 'name': 'sample.mkv', 'sizeBytes': bytes.length},
    'video': {'width': 3840, 'height': 2160, 'codec': 'hevc'},
  });

  setUp(() async {
    // This is an IO unit test; the widget binding's fake HTTP 400 client is not used.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    directory = await Directory.systemTemp.createTemp('cinema-download-test-');
    ranges.clear();
    released = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final match = RegExp(r'bytes=(\d+)-(\d+)')
          .firstMatch(request.headers.value('range')!)!;
      final start = int.parse(match[1]!), end = int.parse(match[2]!);
      ranges.add(start);
      request.response
        ..statusCode = 206
        ..headers.set('content-range', 'bytes $start-$end/${bytes.length}')
        ..contentLength = end - start + 1
        ..add(bytes.sublist(start, end + 1));
      await request.response.close();
    });
    manager = DownloadManager(
      prefs: prefs,
      directory: directory,
      connect: (_, _) async => DownloadConnection(
        uri: Uri.parse('http://127.0.0.1:${server.port}/media'),
        headers: {},
        release: () async {
          released++;
        },
      ),
    );
    await manager.restore();
  });
  tearDown(() async {
    await manager.pauseAll();
    manager.dispose();
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test('downloads exact original bytes, restores completed files, deletes only its file', () async {
    await manager.enqueue(item, resource('test-resource'), '正片');
    await waitFor(
      manager,
      () =>
          manager.jobs.single.state == DownloadState.complete && released == 1,
    );
    final job = manager.jobs.single;
    expect(await File(manager.localPath(job)).readAsBytes(), bytes);
    final unrelated = File('${directory.path}/keep.txt');
    await unrelated.writeAsString('keep');
    final restored = DownloadManager(
      prefs: prefs,
      directory: directory,
      connect: (_, _) async =>
          throw StateError('Offline file must not acquire an account'),
    );
    await restored.restore();
    expect(restored.jobs.single.state, DownloadState.complete);
    expect(restored.jobs.single.resource.width, 3840);
    expect(restored.jobs.single.item.name, item.name);
    await restored.remove(restored.jobs.single);
    expect(await File(manager.localPath(job)).exists(), false);
    expect(await unrelated.readAsString(), 'keep');
    restored.dispose();
  });

  test('resumes persisted partial file from its actual byte length without duplication', () async {
    final pending = DownloadJob(
      item: item,
      resource: resource('partial'),
      label: '正片',
      state: DownloadState.paused,
    );
    await File('${manager.localPath(pending)}.part')
        .writeAsBytes(bytes.sublist(0, 1024 * 1024));
    // Enqueue detects the existing partial file instead of trusting a saved counter.
    await manager.enqueue(item, pending.resource, pending.label);
    await waitFor(
      manager,
      () =>
          manager.jobs.single.state == DownloadState.complete && released == 1,
    );
    expect(ranges, isNot(contains(0)));
    expect(ranges, contains(1024 * 1024));
    expect(
      await File(manager.localPath(manager.jobs.single)).readAsBytes(),
      bytes,
    );
  });

  test('background cancellation during acquisition pauses and releases the eventual lease', () async {
    manager.dispose();
    final ready = Completer<void>();
    final entered = Completer<void>();
    manager = DownloadManager(
      prefs: prefs,
      directory: directory,
      connect: (_, cancellation) async {
        entered.complete();
        await ready.future;
        return DownloadConnection(
          uri: Uri.parse('http://127.0.0.1:${server.port}/media'),
          headers: {},
          release: () async {
            released++;
          },
        );
      },
    );
    await manager.enqueue(item, resource('cancelled'), '正片');
    await entered.future;
    manager.didChangeAppLifecycleState(AppLifecycleState.paused);
    ready.complete();
    await waitFor(
      manager,
      () => manager.jobs.single.state == DownloadState.paused && released == 1,
    );
    expect(ranges, isEmpty);
    manager.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(manager.jobs.single.state, DownloadState.paused);
  });
}
