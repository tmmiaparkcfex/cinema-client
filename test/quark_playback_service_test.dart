import 'dart:convert';
import 'dart:io';

import 'package:cinema_client/core/app_models.dart';
import 'package:cinema_client/quark/quark_account_store.dart';
import 'package:cinema_client/quark/quark_playback_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryAccount extends QuarkAccountStore {
  String cookie = '__puus=synthetic-A';
  String scope = 'session-A';
  @override
  Future<String?> readCookie() async => cookie.isEmpty ? null : cookie;
  @override
  Future<String?> readSessionId() async => scope;
  @override
  Future<void> saveCookie(String value, {bool preserveSession = false}) async {
    cookie = value;
    if (!preserveSession) scope = 'session-${value.hashCode}';
  }

  @override
  Future<void> clear() async {
    cookie = '';
    scope = '';
  }
}

MediaResource resource([String id = 'resource-1']) => MediaResource.fromJson({
  'id': id,
  'share': {
    'id': 'synthetic-share',
    'url': 'https://pan.quark.cn/s/synthetic-share',
  },
  'file': {'id': 'shared-file', 'name': 'movie.mkv', 'sizeBytes': 1024},
  'season': 1,
  'episode': 1,
});

http.Response ok(Object data, {Map<String, String>? headers}) => http.Response(
  jsonEncode({'code': 0, 'data': data}),
  200,
  headers: headers ?? const {},
);
Map<String, dynamic> saved(String fid) => {
  'save_as': {
    'save_as_select_top_fids': [fid],
  },
};
Matcher get cancelled => isA<QuarkException>().having(
  (e) => e.kind,
  'kind',
  QuarkFailureKind.cancelled,
);

class Harness {
  Harness(this.directory) {
    service = QuarkPlaybackService(
      accountStore: account,
      supportDirectory: directory,
      client: MockClient(handle),
    );
  }
  final Directory directory;
  final account = MemoryAccount();
  late final QuarkPlaybackService service;
  final requests = <http.Request>[];
  final files = <String>{'preexisting-file'};
  final deleted = <String>[];
  int saves = 0;
  int failedDeletes = 0;
  Future<http.Response?> Function(http.Request)? intercept;
  File get ledger => File('${directory.path}/quark_temp_files.json');
  Future<List<dynamic>> rows() async =>
      jsonDecode(await ledger.readAsString()) as List;
  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final overridden = await intercept?.call(request);
    if (overridden != null) return overridden;
    final path = request.url.path;
    if (path.endsWith('/share/sharepage/token')) {
      return ok({'stoken': 'synthetic-token'});
    }
    if (path.endsWith('/share/sharepage/detail')) {
      return ok({
        'list': [
          {
            'fid': 'shared-file',
            'file_name': 'movie.mkv',
            'size': 1024,
            'dir': false,
            'share_fid_token': 'synthetic-token',
          },
        ],
      });
    }
    if (path.endsWith('/file/sort')) {
      if (request.url.queryParameters['pdir_fid'] == '0') {
        return ok({
          'list': [
            {
              'fid': 'folder-${account.scope}',
              'file_name': '.cinema-client',
              'dir': true,
            },
          ],
        });
      }
      return ok({
        'list': [
          for (final fid in files)
            {'fid': fid, 'file_name': 'movie.mkv', 'dir': false},
        ],
      });
    }
    if (path.endsWith('/share/sharepage/save')) {
      final fid = 'created-${++saves}';
      files.add(fid);
      return ok(saved(fid));
    }
    if (path.endsWith('/file/download')) {
      return ok([
        {'download_url': 'https://example.invalid/native-video'},
      ]);
    }
    if (path.endsWith('/file/delete')) {
      if (failedDeletes > 0) {
        failedDeletes--;
        return http.Response('{"code":500}', 503);
      }
      final fid =
          (jsonDecode(request.body)['filelist'] as List).single as String;
      deleted.add(fid);
      files.remove(fid);
      return ok({});
    }
    fail('Unexpected synthetic request: $path');
  }
}

void main() {
  late Harness h;
  setUp(() async {
    h = Harness(
      await Directory.systemTemp.createTemp('cinema-service-regression-'),
    );
  });
  tearDown(() => h.service.close());

  test(
    'rejected login cannot replace an existing saved viewer session',
    () async {
      h.intercept = (r) async => r.headers['cookie'] == '__puus=rejected'
          ? http.Response('{"code":31001}', 401)
          : null;
      await expectLater(
        h.service.connectCookie('__puus=rejected'),
        throwsA(isA<QuarkException>()),
      );
      expect(h.account.cookie, '__puus=synthetic-A');
      final lease = await h.service.acquire(resource());
      await lease.release();
    },
  );

  test(
    'validated login stores its rotated cookie before preparing playback',
    () async {
      h.intercept = (r) async => r.headers['cookie'] == '__puus=new-login'
          ? ok(
              {'list': []},
              headers: {'set-cookie': '__puus=validated-rotated; Path=/'},
            )
          : null;
      await h.service.connectCookie('__puus=new-login');
      expect(h.account.cookie, '__puus=validated-rotated');
      final lease = await h.service.acquire(resource());
      expect(lease.headers['Cookie'], '__puus=validated-rotated');
      await lease.release();
    },
  );

  test(
    'clean install obtains a lease and deletes only the newly created file',
    () async {
      expect(await h.ledger.exists(), false);
      final lease = await h.service.acquire(resource());
      expect(lease.mediaUri.scheme, 'https');
      expect(lease.headers['Cookie'], h.account.cookie);
      expect((await h.rows()).single['owned'], true);
      await lease.release();
      expect(h.deleted, ['created-1']);
      expect(h.files, {'preexisting-file'});
      expect(await h.rows(), isEmpty);
    },
  );

  for (final invalid in ['', '{broken', '{}']) {
    test(
      'damaged ledger is preserved and cannot block first playback: $invalid',
      () async {
        await h.ledger.writeAsString(invalid);
        final lease = await h.service.acquire(resource());
        expect(await File('${h.ledger.path}.corrupt').readAsString(), invalid);
        await lease.release();
        expect(await h.rows(), isEmpty);
      },
    );
  }

  test('reads exact saved fid from task response without claiming a same-name existing file', () async {
    h.intercept = (r) async {
      if (r.url.path.endsWith('/share/sharepage/save')) {
        return ok({'task_id': 'task-1'});
      }
      if (r.url.path.endsWith('/task')) {
        h.files.add('task-created');
        return ok({'status': 2, ...saved('task-created')});
      }
      return null;
    };
    final lease = await h.service.acquire(resource());
    expect(lease.savedFid, 'task-created');
    await lease.release();
    expect(h.deleted, ['task-created']);
    expect(h.files, contains('preexisting-file'));
  });

  test(
    'rejects a save result identifying a preexisting file and never deletes it',
    () async {
      h.intercept = (r) async => r.url.path.endsWith('/share/sharepage/save')
          ? ok(saved('preexisting-file'))
          : null;
      await expectLater(
        h.service.acquire(resource()),
        throwsA(isA<QuarkException>()),
      );
      expect(h.deleted, isEmpty);
      expect(
        (await h.rows()).single['beforeFids'],
        contains('preexisting-file'),
      );
    },
  );

  test(
    'cancelled queued request releases the queue so retry can acquire',
    () async {
      final cancellation = QuarkPlaybackCancellation()..cancel();
      await expectLater(
        h.service.acquire(resource(), cancellation: cancellation),
        throwsA(cancelled),
      );
      final lease = await h.service
          .acquire(resource())
          .timeout(const Duration(seconds: 2));
      await lease.release();
    },
  );

  test('cancel during share lookup never submits a save', () async {
    final cancellation = QuarkPlaybackCancellation();
    h.intercept = (r) async {
      if (r.url.path.endsWith('/share/sharepage/detail')) cancellation.cancel();
      return null;
    };
    await expectLater(
      h.service.acquire(resource(), cancellation: cancellation),
      throwsA(cancelled),
    );
    expect(h.saves, 0);
    expect(h.deleted, isEmpty);
  });

  test(
    'cancel after save response cleans the exact new file before completing',
    () async {
      final cancellation = QuarkPlaybackCancellation();
      h.intercept = (r) async {
        if (r.url.path.endsWith('/share/sharepage/save')) cancellation.cancel();
        return null;
      };
      await expectLater(
        h.service.acquire(resource(), cancellation: cancellation),
        throwsA(cancelled),
      );
      expect(h.deleted, ['created-1']);
      expect(
        h.requests.any((r) => r.url.path.endsWith('/file/download')),
        false,
      );
      expect(await h.rows(), isEmpty);
    },
  );

  test(
    'submitted task survives cancellation and is recovered after restart',
    () async {
      final cancellation = QuarkPlaybackCancellation();
      h.intercept = (r) async {
        if (r.url.path.endsWith('/share/sharepage/save')) {
          cancellation.cancel();
          return ok({'task_id': 'pending-1'});
        }
        if (r.url.path.endsWith('/task')) {
          return ok({'status': 2, ...saved('late-created')});
        }
        return null;
      };
      await expectLater(
        h.service.acquire(resource(), cancellation: cancellation),
        throwsA(cancelled),
      );
      expect((await h.rows()).single['status'], 'pending-save-task');
      expect(h.requests.any((r) => r.url.path.endsWith('/task')), false);
      final restarted = QuarkPlaybackService(
        accountStore: h.account,
        supportDirectory: h.directory,
        client: MockClient(h.handle),
      );
      await restarted.cleanupStale();
      restarted.close();
      expect(h.deleted, ['late-created']);
      expect(await h.rows(), isEmpty);
    },
  );

  test(
    'missing task result stays tracked and never falls back to a filename',
    () async {
      h.intercept = (r) async {
        if (r.url.path.endsWith('/share/sharepage/save')) {
          return ok({'task_id': 'pending-missing'});
        }
        if (r.url.path.endsWith('/task')) return ok({'status': 2});
        return null;
      };
      await expectLater(
        h.service.acquire(resource()),
        throwsA(isA<QuarkException>()),
      );
      await h.service.cleanupStale();
      expect(h.deleted, isEmpty);
      expect((await h.rows()).single['taskId'], 'pending-missing');
    },
  );

  test(
    'manual cleanup keeps active playback and retries failed exit cleanup',
    () async {
      final lease = await h.service.acquire(resource());
      await h.service.cleanupStale();
      expect(h.deleted, isEmpty);
      h.failedDeletes = 1;
      await expectLater(lease.release(), throwsA(isA<QuarkException>()));
      expect(await h.rows(), hasLength(1));
      await lease.release();
      expect(h.deleted, ['created-1']);
      expect(await h.rows(), isEmpty);
    },
  );

  test('concurrent release calls share one deletion', () async {
    final lease = await h.service.acquire(resource());
    await Future.wait([lease.release(), lease.release()]);
    expect(h.deleted, ['created-1']);
  });

  test(
    'expired URL refresh reuses the saved file without another transfer',
    () async {
      final lease = await h.service.acquire(resource());
      var refreshed = false;
      h.intercept = (r) async {
        if (r.url.path.endsWith('/file/download')) {
          refreshed = true;
          return ok([
            {'download_url': 'https://example.invalid/refreshed'},
          ]);
        }
        return null;
      };
      await lease.refresh();
      expect(refreshed, true);
      expect(lease.mediaUri.path, '/refreshed');
      expect(h.saves, 1);
      expect(h.deleted, isEmpty);
      await lease.release();
      expect(h.deleted, ['created-1']);
    },
  );

  test(
    'effective folder page size is honored before claiming a save result',
    () async {
      h.intercept = (r) async {
        if (r.url.path.endsWith('/file/sort') &&
            r.url.queryParameters['pdir_fid'] != '0') {
          final page = r.url.queryParameters['_page'];
          return http.Response(
            jsonEncode({
              'code': 0,
              'data': {
                'list': [
                  {'fid': page == '1' ? 'older-other' : 'preexisting-file'},
                ],
              },
              'metadata': {'_size': 1, '_total': 2},
            }),
            200,
          );
        }
        if (r.url.path.endsWith('/share/sharepage/save')) {
          return ok(saved('preexisting-file'));
        }
        return null;
      };
      await expectLater(
        h.service.acquire(resource()),
        throwsA(isA<QuarkException>()),
      );
      expect(h.deleted, isEmpty);
    },
  );

  test(
    'all 21 outstanding files remain tracked and startup can clean every one',
    () async {
      for (var i = 0; i < 21; i++) {
        await h.service.acquire(resource('resource-$i'));
      }
      expect(await h.rows(), hasLength(21));
      final restarted = QuarkPlaybackService(
        accountStore: h.account,
        supportDirectory: h.directory,
        client: MockClient(h.handle),
      );
      await restarted.cleanupStale();
      restarted.close();
      expect(h.deleted, hasLength(21));
      expect(h.deleted, isNot(contains('preexisting-file')));
      expect(await h.rows(), isEmpty);
    },
  );

  test('switching sessions reloads the folder and cannot clean the earlier session', () async {
    final first = await h.service.acquire(resource());
    await h.account.saveCookie('__puus=synthetic-B');
    await h.service.reloadAccount();
    final second = await h.service.acquire(resource('resource-2'));
    final saves = h.requests
        .where((r) => r.url.path.endsWith('/share/sharepage/save'))
        .toList();
    expect(
      jsonDecode(saves[0].body)['to_pdir_fid'],
      isNot(jsonDecode(saves[1].body)['to_pdir_fid']),
    );
    await expectLater(first.release(), throwsA(isA<QuarkException>()));
    await second.release();
    expect(h.deleted, ['created-2']);
    expect((await h.rows()).single['accountId'], 'session-A');
  });

  test(
    'old request cookie rotation cannot overwrite a newly saved login',
    () async {
      h.intercept = (r) async {
        if (r.url.path.endsWith('/share/sharepage/token')) {
          await h.account.saveCookie('__puus=synthetic-B');
          return ok(
            {'stoken': 'synthetic-token'},
            headers: {'set-cookie': '__puus=rotated-A; Path=/'},
          );
        }
        return null;
      };
      final lease = await h.service.acquire(resource());
      expect(h.account.cookie, '__puus=synthetic-B');
      await lease.release();
    },
  );
}
