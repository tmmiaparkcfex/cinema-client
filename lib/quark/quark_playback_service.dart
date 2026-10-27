import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/app_log.dart';
import '../core/app_models.dart';
import 'quark_account_store.dart';

enum QuarkFailureKind {
  authRequired,
  authExpired,
  platformBlocked,
  shareInvalid,
  fileNotFound,
  quota,
  network,
  protocol,
  saveFailed,
  cancelled,
  cleanupFailed,
}

class QuarkException implements Exception {
  const QuarkException(
    this.kind,
    this.message, {
    this.code,
    this.statusCode,
    this.stage,
  });

  final QuarkFailureKind kind;
  final String message;
  final int? code;
  final int? statusCode;
  final String? stage;

  String get userMessage {
    switch (kind) {
      case QuarkFailureKind.authRequired:
        return '需要先连接你的夸克账号，播放才会使用你自己的账号、IP 和流量。';
      case QuarkFailureKind.authExpired:
        return '夸克登录已失效。请重新连接账号后再试，不需要把密码或 Cookie 发给开发者。';
      case QuarkFailureKind.platformBlocked:
        return '夸克暂时限制了这次请求。请稍后重试，或检查账号是否需要验证。';
      case QuarkFailureKind.shareInvalid:
        return '这条分享已失效、被取消或存在访问限制，请切换线路。';
      case QuarkFailureKind.fileNotFound:
        return '分享目录中没有找到这条资源，可能已被分享者移动或删除，请切换线路。';
      case QuarkFailureKind.quota:
        return '你的夸克账号空间不足，无法完成本应用临时转存。请清理空间或改用普通线路。';
      case QuarkFailureKind.network:
        return '连接夸克服务失败，请检查网络后重试。';
      case QuarkFailureKind.protocol:
        return '夸克返回了无法识别的数据结构，可能是接口已变更。';
      case QuarkFailureKind.saveFailed:
        return '转存到本应用专用目录失败，已停止播放，没有删除你原有的文件。';
      case QuarkFailureKind.cancelled:
        return '本次播放准备已取消。已经创建的本应用临时文件会先完成登记和清理。';
      case QuarkFailureKind.cleanupFailed:
        return '播放已停止，但临时文件清理失败。应用会在下次启动时重试。';
    }
  }

  @override
  String toString() =>
      'QuarkException($kind, code=$code, status=$statusCode, stage=$stage)';
}

class QuarkPlaybackLease {
  QuarkPlaybackLease({
    required this.mediaUri,
    required this.headers,
    required this.savedFid,
    required this._release,
    required this._refresh,
  });

  Uri mediaUri;
  Map<String, String> headers;
  final String savedFid;
  final Future<void> Function() _release;
  final Future<({Uri uri, Map<String, String> headers})> Function() _refresh;
  bool _released = false;
  Future<void>? _releasing;

  Future<void> release() {
    if (_released) return Future<void>.value();
    return _releasing ??= () async {
      try {
        await _release();
        _released = true;
      } finally {
        _releasing = null;
      }
    }();
  }

  Future<void> refresh() async {
    if (_released || _releasing != null) {
      throw StateError('Playback lease already released');
    }
    final refreshed = await _refresh();
    mediaUri = refreshed.uri;
    headers = refreshed.headers;
  }

  @override
  String toString() => 'QuarkPlaybackLease(fid=$savedFid)';
}

class QuarkPlaybackCancellation {
  bool _cancelled = false;
  final Completer<void> _cancelledSignal = Completer<void>();

  bool get isCancelled => _cancelled;

  Future<void> get whenCancelled => _cancelledSignal.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancelledSignal.complete();
  }

  void throwIfCancelled() {
    if (!_cancelled) return;
    throw const QuarkException(
      QuarkFailureKind.cancelled,
      'playback preparation cancelled',
      stage: 'cancelled',
    );
  }
}

class _QuarkResponse {
  const _QuarkResponse(this.status, this.json);

  final int status;
  final Map<String, dynamic>? json;

  int? get code => json?['code'] is num ? (json?['code'] as num).toInt() : null;
  String get message =>
      (json?['message'] ?? json?['msg'] ?? json?['error'] ?? '').toString();
  Map<String, dynamic> get data {
    final value = json?['data'];
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return const {};
  }
}

class _ShareFile {
  const _ShareFile(this.fid, this.token, this.name, this.size);

  final String fid;
  final String token;
  final String name;
  final int size;
}

class _SavedFile {
  const _SavedFile({
    required this.fid,
    required this.operationId,
    required this.accountId,
    this.taskId,
  });

  final String fid;
  final String operationId;
  final String accountId;
  final String? taskId;
}

class QuarkPlaybackService {
  QuarkPlaybackService({
    required this.accountStore,
    required this.supportDirectory,
    http.Client? client,
  }) : _client = client ?? http.Client();

  static const _apiBase = 'https://drive-pc.quark.cn/1/clouddrive/';
  static const _stagingFolderName = '.cinema-client';
  static const _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) quark-cloud-drive/2.5.56 Chrome/100.0.4896.160 '
      'Electron/18.3.3.5.12-a038f7b798 Safari/537.36 Channel/pckk_other_ch';
  static const _requestTimeout = Duration(seconds: 25);

  final QuarkAccountStore accountStore;
  final Directory supportDirectory;
  final http.Client _client;

  String _cookie = '';
  String _accountId = '';
  String? _stagingFolderId;
  String? _stagingFolderAccountId;
  Future<void> _acquireTail = Future<void>.value();
  Future<void> _ledgerTail = Future<void>.value();
  int _operationCounter = 0;
  final Set<String> _activeFiles = {};

  File get _ledgerFile =>
      File('${supportDirectory.path}/quark_temp_files.json');

  Future<bool> get hasAccount async =>
      (await accountStore.readCookie()) != null;
  Future<int> get pendingCleanupCount async => (await _ledgerRead()).length;

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final previous = _acquireTail;
    final done = Completer<void>();
    _acquireTail = done.future;
    return () async {
      await previous;
      try {
        return await action();
      } finally {
        done.complete();
      }
    }();
  }

  Future<void> reloadAccount() => _exclusive(_loadAccount);

  Future<void> _loadAccount() async {
    _cookie = await accountStore.readCookie() ?? '';
    _accountId = await accountStore.readSessionId() ?? '';
    _stagingFolderId = null;
    _stagingFolderAccountId = null;
  }

  Future<void> _ensureCookie({bool required = true}) async {
    if (_cookie.isEmpty) await _loadAccount();
    if (required && _cookie.isEmpty) {
      throw const QuarkException(
        QuarkFailureKind.authRequired,
        'no viewer cookie',
        stage: 'account',
      );
    }
  }

  Uri _uri(String endpoint, [Map<String, String> params = const {}]) {
    return Uri.parse('$_apiBase$endpoint')
        .replace(queryParameters: {'pr': 'ucpro', 'fr': 'pc', ...params});
  }

  Map<String, String> _headers({bool jsonBody = false}) => {
    'Origin': 'https://pan.quark.cn',
    'Referer': 'https://pan.quark.cn/',
    'Accept': 'application/json, text/plain, */*',
    'User-Agent': _desktopUserAgent,
    if (_cookie.isNotEmpty) 'Cookie': _cookie,
    if (jsonBody) 'Content-Type': 'application/json',
  };

  Future<_QuarkResponse> _request(
    String method,
    String endpoint, {
    Map<String, String> params = const {},
    Map<String, dynamic>? body,
    bool allowEmptyCookie = false,
  }) async {
    if (!allowEmptyCookie) await _ensureCookie();
    try {
      final request = http.Request(method, _uri(endpoint, params));
      request.headers.addAll(_headers(jsonBody: body != null));
      if (body != null) request.body = jsonEncode(body);
      final response = await (() async {
        final streamed = await _client.send(request);
        return http.Response.fromStream(streamed);
      })().timeout(_requestTimeout);
      await _captureRotatedCookie(response);
      Map<String, dynamic>? json;
      try {
        final decoded = jsonDecode(
          utf8.decode(response.bodyBytes, allowMalformed: true),
        );
        if (decoded is Map<String, dynamic>) json = decoded;
      } catch (_) {
        json = null;
      }
      AppLog.info(
        'quark',
        '$method $endpoint status=${response.statusCode} code=${json?['code'] ?? '-'}',
      );
      return _QuarkResponse(response.statusCode, json);
    } on TimeoutException {
      throw const QuarkException(
        QuarkFailureKind.network,
        'quark request timeout',
      );
    } on SocketException catch (error) {
      AppLog.error('quark', error);
      throw QuarkException(QuarkFailureKind.network, error.message);
    } on http.ClientException catch (error) {
      AppLog.error('quark', error);
      throw QuarkException(QuarkFailureKind.network, error.message);
    }
  }

  Future<void> _captureRotatedCookie(http.Response response) async {
    final setCookie = response.headers['set-cookie'];
    if (setCookie == null || setCookie.isEmpty) return;
    final cookies = <String, String>{};
    for (final part in _cookie.split(';')) {
      final index = part.indexOf('=');
      if (index > 0) {
        cookies[part.substring(0, index).trim()] = part
            .substring(index + 1)
            .trim();
      }
    }
    var changed = false;
    final pattern = RegExp(r'(__puus|__pus)=([^;,\s]+)');
    for (final match in pattern.allMatches(setCookie)) {
      final name = match.group(1)!;
      final value = match.group(2)!;
      if (cookies[name] != value) {
        cookies[name] = value;
        changed = true;
      }
    }
    if (!changed) return;
    _cookie = cookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
    // A login UI may have saved a new session while the old request was in flight.
    // Never overwrite that new session with the old account's rotated cookie.
    if (_accountId.isNotEmpty &&
        await accountStore.readSessionId() == _accountId) {
      await accountStore.saveCookie(_cookie, preserveSession: true);
    }
  }

  void _ensureSuccess(
    _QuarkResponse response, {
    QuarkFailureKind fallback = QuarkFailureKind.protocol,
    String? stage,
  }) {
    if (response.status == 401) {
      throw QuarkException(
        QuarkFailureKind.authExpired,
        'unauthorized',
        statusCode: response.status,
        stage: stage,
      );
    }
    if (response.status == 403 ||
        response.status == 412 ||
        response.status == 429) {
      throw QuarkException(
        QuarkFailureKind.platformBlocked,
        response.message,
        code: response.code,
        statusCode: response.status,
        stage: stage,
      );
    }
    if (response.status < 200 || response.status >= 300 || response.code != 0) {
      final code = response.code;
      final message = response.message;
      final kind = switch (code) {
        41010 || 41011 || 41012 => QuarkFailureKind.shareInvalid,
        21001 => QuarkFailureKind.fileNotFound,
        _ when RegExp(r'空间|容量|quota', caseSensitive: false).hasMatch(message) =>
          QuarkFailureKind.quota,
        _ => fallback,
      };
      throw QuarkException(
        kind,
        message,
        code: code,
        statusCode: response.status,
        stage: stage,
      );
    }
  }

  Future<void> validateAccount() => _exclusive(_validateAccount);

  Future<void> connectCookie(String cookie) => _exclusive(() async {
    final previousCookie = _cookie;
    final previousAccount = _accountId;
    _cookie = cookie;
    _accountId = '';
    try {
      await _validateAccount();
      await accountStore.saveCookie(_cookie);
      await _loadAccount();
    } catch (_) {
      _cookie = previousCookie;
      _accountId = previousAccount;
      rethrow;
    }
  });

  Future<void> _validateAccount() async {
    await _ensureCookie();
    final response = await _request(
      'GET',
      'file/sort',
      params: const {
        'pdir_fid': '0',
        '_page': '1',
        '_size': '1',
        '_fetch_total': '1',
      },
    );
    if (response.code == 31001 ||
        response.code == 401 ||
        response.status == 401) {
      throw const QuarkException(
        QuarkFailureKind.authExpired,
        'quark session rejected',
        stage: 'validate',
      );
    }
    _ensureSuccess(
      response,
      fallback: QuarkFailureKind.authExpired,
      stage: 'validate',
    );
  }

  Future<QuarkPlaybackLease> acquire(
    MediaResource resource, {
    void Function(String stage)? onStage,
    QuarkPlaybackCancellation? cancellation,
  }) {
    return _exclusive(() async {
      cancellation?.throwIfCancelled();
      return _acquire(resource, onStage: onStage, cancellation: cancellation);
    });
  }

  Future<QuarkPlaybackLease> _acquire(
    MediaResource resource, {
    void Function(String stage)? onStage,
    QuarkPlaybackCancellation? cancellation,
  }) async {
    if (resource.shareId.isEmpty || resource.fileId.isEmpty) {
      throw const QuarkException(
        QuarkFailureKind.protocol,
        'resource lacks share or file id',
        stage: 'validate-resource',
      );
    }
    await _ensureCookie();
    cancellation?.throwIfCancelled();
    final accountId = _accountId;
    final operationId =
        '${DateTime.now().microsecondsSinceEpoch}-${++_operationCounter}';

    onStage?.call('正在确认分享');
    cancellation?.throwIfCancelled();
    final passcode = resource.sharePassword.isNotEmpty
        ? resource.sharePassword
        : (Uri.tryParse(resource.shareUrl)?.queryParameters['pwd'] ?? '');
    final tokenResponse = await _request(
      'POST',
      'share/sharepage/token',
      body: {
        'pwd_id': resource.shareId,
        'passcode': passcode,
        'support_visit_limit_private_share': true,
      },
    );
    cancellation?.throwIfCancelled();
    _ensureSuccess(
      tokenResponse,
      fallback: QuarkFailureKind.shareInvalid,
      stage: 'share-token',
    );
    final stoken = tokenResponse.data['stoken']?.toString() ?? '';
    if (stoken.isEmpty) {
      throw const QuarkException(
        QuarkFailureKind.shareInvalid,
        'stoken missing',
        stage: 'share-token',
      );
    }

    onStage?.call('正在定位资源');
    final shareFile = await _locateShareFile(
      resource: resource,
      password: passcode,
      stoken: stoken,
      cancellation: cancellation,
    );

    onStage?.call('正在准备应用专用目录');
    cancellation?.throwIfCancelled();
    final folderId = await _ensureStagingFolder(cancellation: cancellation);

    onStage?.call('正在转存到你的网盘');
    cancellation?.throwIfCancelled();
    _SavedFile? savedFile;
    try {
      // After save has been submitted it must finish resolving so that the new
      // file can be registered and cleaned even when the UI was cancelled.
      savedFile = await _saveToStaging(
        resource: resource,
        stoken: stoken,
        folderId: folderId,
        shareFile: shareFile,
        operationId: operationId,
        accountId: accountId,
        cancellation: cancellation,
      );
      await _ledgerComplete(savedFile, folderId, resource.id);
      cancellation?.throwIfCancelled();

      onStage?.call('正在获取播放地址');
      cancellation?.throwIfCancelled();
      final url = await _downloadUrl(savedFile.fid, cancellation: cancellation);
      if (url == null) {
        throw const QuarkException(
          QuarkFailureKind.protocol,
          'download url missing',
          stage: 'download-url',
        );
      }
      AppLog.info('quark-playback', 'lease-ready');
      final leaseFile = savedFile;
      _activeFiles.add('${leaseFile.accountId}:${leaseFile.fid}');
      return QuarkPlaybackLease(
        mediaUri: url,
        headers: {
          'Referer': 'https://pan.quark.cn/',
          'User-Agent': _desktopUserAgent,
          'Cookie': _cookie,
        },
        savedFid: leaseFile.fid,
        release: () => _exclusive(() async {
          _activeFiles.remove('${leaseFile.accountId}:${leaseFile.fid}');
          await _releaseFid(leaseFile.fid, accountId: leaseFile.accountId);
        }),
        refresh: () => _exclusive(() async {
          await _ensureCookie();
          if (_accountId != leaseFile.accountId) {
            throw const QuarkException(
              QuarkFailureKind.authRequired,
              'playback session changed',
              stage: 'refresh',
            );
          }
          final refreshed = await _downloadUrl(leaseFile.fid);
          if (refreshed == null) {
            throw const QuarkException(
              QuarkFailureKind.protocol,
              'download URL missing',
              stage: 'refresh',
            );
          }
          return (
            uri: refreshed,
            headers: {
              'Referer': 'https://pan.quark.cn/',
              'User-Agent': _desktopUserAgent,
              'Cookie': _cookie,
            },
          );
        }),
      );
    } catch (error) {
      final created = savedFile;
      if (created != null) {
        await _releaseFid(
          created.fid,
          accountId: created.accountId,
          suppress: true,
        );
      }
      rethrow;
    }
  }

  Future<_ShareFile> _locateShareFile({
    required MediaResource resource,
    required String password,
    required String stoken,
    QuarkPlaybackCancellation? cancellation,
  }) async {
    final directories = <String>['0'];
    final seenDirectories = <String>{'0'};
    var requests = 0;
    while (directories.isNotEmpty && requests < 50) {
      final folder = directories.removeAt(0);
      var page = 1;
      while (page <= 20 && requests < 50) {
        cancellation?.throwIfCancelled();
        final response = await _request(
          'GET',
          'share/sharepage/detail',
          params: {
            'pwd_id': resource.shareId,
            'stoken': stoken,
            'pdir_fid': folder,
            'force': '0',
            '_page': '$page',
            '_size': '100',
            '_fetch_total': '1',
            '_fetch_share': '1',
          },
        );
        requests++;
        cancellation?.throwIfCancelled();
        _ensureSuccess(
          response,
          fallback: QuarkFailureKind.protocol,
          stage: 'share-detail',
        );
        final rows = response.data['list'];
        if (rows is! List) break;
        for (final raw in rows) {
          if (raw is! Map) continue;
          final row = raw.cast<String, dynamic>();
          final fid = row['fid']?.toString() ?? '';
          final name = row['file_name']?.toString() ?? '';
          final isDirectory = row['dir'] == true || row['dir'] == 1;
          if (isDirectory) {
            if (fid.isNotEmpty &&
                seenDirectories.add(fid) &&
                seenDirectories.length <= 160) {
              directories.add(fid);
            }
            continue;
          }
          final size = int.tryParse(row['size']?.toString() ?? '') ?? 0;
          final sizeMatches =
              size == 0 ||
              resource.sizeBytes == 0 ||
              size == resource.sizeBytes;
          final idMatches = fid == resource.fileId;
          final fallbackNameMatches =
              resource.fileId.isEmpty &&
              name == resource.fileName &&
              sizeMatches;
          if ((idMatches && sizeMatches) || fallbackNameMatches) {
            return _ShareFile(
              fid,
              row['share_fid_token']?.toString() ?? '',
              name,
              size,
            );
          }
        }
        final metadata = response.json?['metadata'];
        final total = metadata is Map
            ? int.tryParse(metadata['_total']?.toString() ?? '')
            : null;
        final pageSize = metadata is Map
            ? int.tryParse(metadata['_size']?.toString() ?? '') ?? 100
            : 100;
        if (rows.isEmpty || (total != null && page * pageSize >= total)) break;
        page++;
      }
    }
    throw const QuarkException(
      QuarkFailureKind.fileNotFound,
      'share file not located',
      stage: 'locate',
    );
  }

  Future<String> _ensureStagingFolder({
    QuarkPlaybackCancellation? cancellation,
  }) async {
    if (_stagingFolderId != null && _stagingFolderAccountId == _accountId) {
      return _stagingFolderId!;
    }
    cancellation?.throwIfCancelled();
    final rows = await _folderRows('0', cancellation);
    for (final row in rows) {
      final isDirectory = row['dir'] == true || row['dir'] == 1;
      if (isDirectory && row['file_name'] == _stagingFolderName) {
        final id = row['fid']?.toString() ?? '';
        if (id.isNotEmpty) {
          _stagingFolderId = id;
          _stagingFolderAccountId = _accountId;
          return id;
        }
      }
    }
    cancellation?.throwIfCancelled();
    final create = await _request(
      'POST',
      'file',
      body: {
        'pdir_fid': '0',
        'file_name': _stagingFolderName,
        'dir_path': '',
        'dir_init_lock': false,
      },
    );
    _ensureSuccess(
      create,
      fallback: QuarkFailureKind.saveFailed,
      stage: 'folder-create',
    );
    final id = create.data['fid']?.toString() ?? '';
    if (id.isEmpty) {
      throw const QuarkException(
        QuarkFailureKind.saveFailed,
        'folder fid missing',
        stage: 'folder-create',
      );
    }
    _stagingFolderId = id;
    _stagingFolderAccountId = _accountId;
    return id;
  }

  Future<_SavedFile> _saveToStaging({
    required MediaResource resource,
    required String stoken,
    required String folderId,
    required _ShareFile shareFile,
    required String operationId,
    required String accountId,
    QuarkPlaybackCancellation? cancellation,
  }) async {
    final beforeFids = (await _folderRows(folderId, cancellation))
        .map((row) => row['fid']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    cancellation?.throwIfCancelled();
    await _ledgerUpsert(
      operationId: operationId,
      accountId: accountId,
      folderId: folderId,
      resourceId: resource.id,
      status: 'submitting',
      beforeFids: beforeFids.toList(),
      sharedFid: shareFile.fid,
    );
    cancellation?.throwIfCancelled();
    final response = await _request(
      'POST',
      'share/sharepage/save',
      body: {
        'fid_list': [shareFile.fid],
        'fid_token_list': [shareFile.token],
        'to_pdir_fid': folderId,
        'pwd_id': resource.shareId,
        'stoken': stoken,
        'pdir_fid': '0',
        'scene': 'link',
        'ondup': 2,
      },
    );
    _ensureSuccess(
      response,
      fallback: QuarkFailureKind.saveFailed,
      stage: 'save',
    );
    final data = response.data;
    String? fid = _extractSavedFid(data);
    final taskId = data['task_id']?.toString() ?? '';

    if (fid == null && taskId.isNotEmpty) {
      try {
        await _ledgerUpsert(
          operationId: operationId,
          accountId: accountId,
          folderId: folderId,
          resourceId: resource.id,
          taskId: taskId,
          status: 'pending-save-task',
        );
      } catch (error) {
        // The submitted Quark task still has to be resolved below even if the
        // local tracking write fails; otherwise ownership would be lost.
        AppLog.error('quark-ledger', error);
      }
      var completed = false;
      for (var attempt = 0; attempt < 30; attempt++) {
        // A submitted task is durably tracked. Cancellation may stop polling;
        // startup/manual cleanup will resolve this exact task, never a filename.
        cancellation?.throwIfCancelled();
        final task = await _request(
          'GET',
          'task',
          params: {'task_id': taskId, 'retry_index': '$attempt'},
        );
        _ensureSuccess(
          task,
          fallback: QuarkFailureKind.saveFailed,
          stage: 'save-task',
        );
        final status = task.data['status'];
        if (status == 2) {
          fid = _extractSavedFid(task.data);
          if (fid == null) {
            throw QuarkException(
              QuarkFailureKind.saveFailed,
              'save task completed without a new fid: $taskId',
              stage: 'save-task',
            );
          }
          completed = true;
          break;
        }
        if (status == 3) {
          throw QuarkException(
            QuarkFailureKind.saveFailed,
            'save task failed: $taskId',
            stage: 'save-task',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
      if (!completed) {
        throw QuarkException(
          QuarkFailureKind.saveFailed,
          'save task timeout: $taskId',
          stage: 'save-task',
        );
      }
    }

    final createdFid = fid;
    if (createdFid == null ||
        createdFid.isEmpty ||
        createdFid == shareFile.fid ||
        beforeFids.contains(createdFid)) {
      throw const QuarkException(
        QuarkFailureKind.saveFailed,
        'save response did not prove a new owned file',
        stage: 'save',
      );
    }
    return _SavedFile(
      fid: createdFid,
      operationId: operationId,
      accountId: accountId,
      taskId: taskId.isEmpty ? null : taskId,
    );
  }

  Future<List<Map<String, dynamic>>> _folderRows(
    String folderId,
    QuarkPlaybackCancellation? cancellation,
  ) async {
    final result = <Map<String, dynamic>>[];
    for (var page = 1; page <= 100; page++) {
      cancellation?.throwIfCancelled();
      final response = await _request(
        'GET',
        'file/sort',
        params: {
          'pdir_fid': folderId,
          '_page': '$page',
          '_size': '100',
          '_fetch_total': '1',
        },
      );
      cancellation?.throwIfCancelled();
      _ensureSuccess(response, stage: 'folder-snapshot');
      final rows = response.data['list'];
      if (rows is! List) {
        throw const QuarkException(
          QuarkFailureKind.protocol,
          'folder listing missing',
          stage: 'folder-snapshot',
        );
      }
      result.addAll(
        rows.whereType<Map>().map((row) => row.cast<String, dynamic>()),
      );
      final metadata = response.json?['metadata'];
      final total = metadata is Map
          ? int.tryParse(metadata['_total']?.toString() ?? '')
          : null;
      final pageSize = metadata is Map
          ? int.tryParse(metadata['_size']?.toString() ?? '') ?? 100
          : 100;
      if (pageSize <= 0 ||
          (rows.isEmpty && total != null && result.length < total)) {
        throw const QuarkException(
          QuarkFailureKind.protocol,
          'incomplete folder listing',
          stage: 'folder-snapshot',
        );
      }
      if (total != null ? page * pageSize >= total : rows.length < pageSize) {
        return result;
      }
    }
    throw const QuarkException(
      QuarkFailureKind.saveFailed,
      'folder snapshot limit reached',
      stage: 'folder-snapshot',
    );
  }

  String? _extractSavedFid(Map<String, dynamic> data) {
    String? valueOf(Object? value) {
      final fid = value?.toString() ?? '';
      return fid.isEmpty ? null : fid;
    }

    final saveAs =
        data['save_as'] ??
        (data['task_resp'] is Map
            ? (data['task_resp'] as Map)['save_as']
            : null) ??
        (data['task_resp'] is Map && (data['task_resp'] as Map)['data'] is Map
            ? ((data['task_resp'] as Map)['data'] as Map)['save_as']
            : null);
    if (saveAs is Map) {
      final values =
          saveAs['save_as_select_top_fids'] ?? saveAs['save_as_top_fids'];
      if (values is List && values.isNotEmpty) {
        final fid = valueOf(values.first);
        if (fid != null) return fid;
      }
      final firstVideo = saveAs['first_video'];
      if (firstVideo is Map) {
        final fid = valueOf(firstVideo['fid']);
        if (fid != null) return fid;
      }
      final fid = valueOf(saveAs['fid']);
      if (fid != null) return fid;
    }
    final fidList = data['fid_list'];
    if (fidList is List && fidList.isNotEmpty) return valueOf(fidList.first);
    return null;
  }

  Future<Uri?> _downloadUrl(
    String fid, {
    QuarkPlaybackCancellation? cancellation,
  }) async {
    for (final desktop in [false, true]) {
      cancellation?.throwIfCancelled();
      final response = await _request(
        'POST',
        'file/download',
        params: desktop
            ? const {'sys': 'win32', 've': '2.5.56', 'ut': '', 'guid': ''}
            : const {},
        body: {
          'fids': [fid],
        },
      );
      cancellation?.throwIfCancelled();
      if (response.status < 200 || response.status >= 300) {
        _ensureSuccess(response, stage: 'download-url');
      }
      if ((response.status == 401) || response.code == 31001) {
        throw const QuarkException(
          QuarkFailureKind.authExpired,
          'download session rejected',
          stage: 'download-url',
        );
      }
      if (response.code != 0 && response.code != 23018) {
        _ensureSuccess(response, stage: 'download-url');
      }
      if (response.code == 0) {
        final data = response.json?['data'];
        Map<String, dynamic>? item;
        if (data is List && data.isNotEmpty && data.first is Map) {
          item = (data.first as Map).cast<String, dynamic>();
        } else if (data is Map) {
          item = data.cast<String, dynamic>();
        }
        final value = item?['download_url']?.toString() ?? '';
        if (value.isNotEmpty) {
          final uri = Uri.tryParse(value);
          if (uri != null && uri.hasScheme) return uri;
        }
      }
    }
    return null;
  }

  Future<void> _releaseFid(
    String fid, {
    required String accountId,
    bool suppress = false,
  }) async {
    try {
      await _ensureCookie();
      if (accountId.isEmpty || _accountId != accountId) {
        throw const QuarkException(
          QuarkFailureKind.cleanupFailed,
          'temporary file account mismatch',
          stage: 'cleanup-auth',
        );
      }
      final response = await _request(
        'POST',
        'file/delete',
        body: {
          'action_type': 1,
          'filelist': [fid],
          'exclude_fids': [],
        },
      );
      final ok =
          response.status >= 200 &&
          response.status < 300 &&
          (response.code == 0 || response.code == 23004);
      if (!ok) {
        throw QuarkException(
          QuarkFailureKind.cleanupFailed,
          response.message,
          code: response.code,
          statusCode: response.status,
          stage: 'cleanup',
        );
      }
      await _ledgerRemove(fid, accountId);
      AppLog.info('quark-playback', 'temp-file-released');
    } catch (error) {
      AppLog.error('quark-playback', error);
      if (!suppress) rethrow;
    }
  }

  Future<void> cleanupStale() => _exclusive(_cleanupStale);

  Future<void> _cleanupStale() async {
    await _ensureCookie(required: false);
    if (_cookie.isEmpty) return;
    final entries = await _ledgerRead();
    if (entries.isEmpty) return;
    for (final entry in entries) {
      if (entry['accountId'] != _accountId) continue;
      if (entry['status'] == 'pending-save-task') {
        try {
          await _recoverSaveTask(entry);
        } catch (error) {
          AppLog.error('quark-task-cleanup', error);
        }
        continue;
      }
      if (entry['status'] != 'ready' || entry['owned'] != true) continue;
      final fid = entry['fid']?.toString() ?? '';
      if (fid.isEmpty || _activeFiles.contains('$_accountId:$fid')) continue;
      await _releaseFid(fid, accountId: _accountId, suppress: true);
    }
  }

  Future<void> _recoverSaveTask(Map<String, dynamic> entry) async {
    final taskId = entry['taskId']?.toString() ?? '';
    final operationId = entry['operationId']?.toString() ?? '';
    final before = entry['beforeFids'];
    if (taskId.isEmpty || operationId.isEmpty || before is! List) return;
    final response = await _request(
      'GET',
      'task',
      params: {'task_id': taskId, 'retry_index': '0'},
    );
    _ensureSuccess(
      response,
      fallback: QuarkFailureKind.cleanupFailed,
      stage: 'cleanup-task',
    );
    if (response.data['status'] == 3) {
      await _ledgerMutate(
        (rows) => rows.removeWhere(
          (row) =>
              row['operationId'] == operationId &&
              row['accountId'] == _accountId,
        ),
      );
      return;
    }
    if (response.data['status'] != 2) return;
    final fid = _extractSavedFid(response.data);
    if (fid == null || fid == entry['sharedFid'] || before.contains(fid)) {
      return;
    }
    final saved = _SavedFile(
      fid: fid,
      operationId: operationId,
      accountId: _accountId,
      taskId: taskId,
    );
    await _ledgerComplete(
      saved,
      entry['folderId']?.toString() ?? '',
      entry['resourceId']?.toString() ?? '',
    );
    if (!_activeFiles.contains('$_accountId:$fid')) {
      await _releaseFid(fid, accountId: _accountId);
    }
  }

  Future<List<Map<String, dynamic>>> _ledgerRead() async {
    try {
      if (!await _ledgerFile.exists()) return <Map<String, dynamic>>[];
      final text = await _ledgerFile.readAsString();
      if (text.trim().isEmpty) throw const FormatException('empty ledger');
      final value = jsonDecode(text);
      if (value is! List) throw const FormatException('ledger is not a list');
      return value
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    } catch (error) {
      AppLog.error('quark-ledger', error);
      try {
        if (await _ledgerFile.exists()) {
          final backup = File('${_ledgerFile.path}.corrupt');
          if (!await backup.exists()) await _ledgerFile.copy(backup.path);
        }
      } catch (backupError) {
        AppLog.error('quark-ledger-backup', backupError);
      }
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _ledgerWrite(List<Map<String, dynamic>> entries) async {
    await _ledgerFile.parent.create(recursive: true);
    final temporary = File('${_ledgerFile.path}.tmp');
    await temporary.writeAsString(jsonEncode(entries), flush: true);
    await temporary.rename(_ledgerFile.path);
  }

  Future<void> _ledgerMutate(void Function(List<Map<String, dynamic>>) mutate) {
    final previous = _ledgerTail;
    final done = Completer<void>();
    _ledgerTail = done.future;
    return () async {
      await previous;
      try {
        final entries = await _ledgerRead();
        mutate(entries);
        await _ledgerWrite(entries);
      } finally {
        done.complete();
      }
    }();
  }

  Future<void> _ledgerUpsert({
    required String operationId,
    required String accountId,
    required String folderId,
    required String resourceId,
    required String status,
    String? fid,
    String? taskId,
    List<String>? beforeFids,
    String? sharedFid,
    bool? owned,
  }) {
    return _ledgerMutate((entries) {
      var createdAt = DateTime.now().millisecondsSinceEpoch;
      Map<String, dynamic> previous = {};
      for (final entry in entries) {
        if (entry['operationId'] == operationId) {
          previous = entry;
          createdAt =
              int.tryParse(entry['createdAt']?.toString() ?? '') ?? createdAt;
          break;
        }
      }
      entries.removeWhere((entry) => entry['operationId'] == operationId);
      entries.add({
        ...previous,
        'operationId': operationId,
        'accountId': accountId,
        'folderId': folderId,
        'resourceId': resourceId,
        'status': status,
        'fid': ?fid,
        'taskId': ?taskId,
        'beforeFids': ?beforeFids,
        'sharedFid': ?sharedFid,
        'owned': ?owned,
        'createdAt': createdAt,
      });
    });
  }

  Future<void> _ledgerComplete(
    _SavedFile saved,
    String folderId,
    String resourceId,
  ) {
    return _ledgerUpsert(
      operationId: saved.operationId,
      accountId: saved.accountId,
      folderId: folderId,
      resourceId: resourceId,
      fid: saved.fid,
      taskId: saved.taskId,
      status: 'ready',
      owned: true,
    );
  }

  Future<void> _ledgerRemove(String fid, String accountId) {
    return _ledgerMutate((entries) {
      entries.removeWhere(
        (entry) => entry['fid'] == fid && entry['accountId'] == accountId,
      );
    });
  }

  void close() => _client.close();
}
