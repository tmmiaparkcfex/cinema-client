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
      case QuarkFailureKind.cleanupFailed:
        return '播放已停止，但临时文件清理失败。应用会在下次启动时重试。';
    }
  }

  @override
  String toString() => 'QuarkException($kind, code=$code, status=$statusCode, stage=$stage)';
}

class QuarkPlaybackLease {
  QuarkPlaybackLease({
    required this.mediaUri,
    required this.headers,
    required this.savedFid,
    required this._release,
  });

  final Uri mediaUri;
  final Map<String, String> headers;
  final String savedFid;
  final Future<void> Function() _release;
  bool _released = false;

  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _release();
  }

  @override
  String toString() => 'QuarkPlaybackLease(fid=$savedFid)';
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
  String? _stagingFolderId;

  File get _ledgerFile => File('${supportDirectory.path}/quark_temp_files.json');

  Future<bool> get hasAccount async => (await accountStore.readCookie()) != null;

  Future<void> reloadAccount() async {
    _cookie = await accountStore.readCookie() ?? '';
  }

  Future<void> _ensureCookie({bool required = true}) async {
    if (_cookie.isNotEmpty) return;
    _cookie = await accountStore.readCookie() ?? '';
    if (required && _cookie.isEmpty) {
      throw const QuarkException(
        QuarkFailureKind.authRequired,
        'no viewer cookie',
        stage: 'account',
      );
    }
  }

  Uri _uri(String endpoint, [Map<String, String> params = const {}]) {
    return Uri.parse('$_apiBase$endpoint').replace(
      queryParameters: {
        'pr': 'ucpro',
        'fr': 'pc',
        ...params,
      },
    );
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
      final streamed = await _client.send(request).timeout(_requestTimeout);
      final response = await http.Response.fromStream(streamed);
      _captureRotatedCookie(response);
      Map<String, dynamic>? json;
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
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

  void _captureRotatedCookie(http.Response response) {
    final setCookie = response.headers['set-cookie'];
    if (setCookie == null || setCookie.isEmpty) return;
    final cookies = <String, String>{};
    for (final part in _cookie.split(';')) {
      final index = part.indexOf('=');
      if (index > 0) cookies[part.substring(0, index).trim()] = part.substring(index + 1).trim();
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
    _cookie = cookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
    unawaited(accountStore.saveCookie(_cookie).catchError((Object error) {
      AppLog.error('quark-account', error);
    }));
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
    if (response.status == 403 || response.status == 412 || response.status == 429) {
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

  Future<void> validateAccount() async {
    await _ensureCookie();
    final response = await _request(
      'GET',
      'file/sort',
      params: const {'pdir_fid': '0', '_page': '1', '_size': '1', '_fetch_total': '1'},
    );
    if (response.code == 31001 || response.code == 401 || response.status == 401) {
      throw const QuarkException(
        QuarkFailureKind.authExpired,
        'quark session rejected',
        stage: 'validate',
      );
    }
    _ensureSuccess(response, fallback: QuarkFailureKind.authExpired, stage: 'validate');
  }

  Future<QuarkPlaybackLease> acquire(
    MediaResource resource, {
    void Function(String stage)? onStage,
  }) async {
    await _ensureCookie();
    if (resource.shareId.isEmpty || resource.fileId.isEmpty) {
      throw const QuarkException(
        QuarkFailureKind.protocol,
        'resource lacks share or file id',
        stage: 'validate-resource',
      );
    }

    onStage?.call('正在确认分享');
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
    );

    onStage?.call('正在准备应用专用目录');
    final folderId = await _ensureStagingFolder();

    onStage?.call('正在转存到你的网盘');
    String? savedFid;
    try {
      savedFid = await _saveToStaging(
        resource: resource,
        stoken: stoken,
        folderId: folderId,
        shareFile: shareFile,
      );
      await _ledgerAdd(savedFid, folderId, resource.id);

      onStage?.call('正在获取播放地址');
      final url = await _downloadUrl(savedFid);
      if (url == null) {
        throw const QuarkException(
          QuarkFailureKind.protocol,
          'download url missing',
          stage: 'download-url',
        );
      }
      AppLog.info('quark-playback', 'lease-ready resource=${resource.id}');
      return QuarkPlaybackLease(
        mediaUri: url,
        headers: {
          'Referer': 'https://pan.quark.cn/',
          'User-Agent': _desktopUserAgent,
          'Cookie': _cookie,
        },
        savedFid: savedFid,
        release: () => _releaseFid(savedFid!),
      );
    } catch (error) {
      if (savedFid != null) {
        await _releaseFid(savedFid, suppress: true);
      }
      rethrow;
    }
  }

  Future<_ShareFile> _locateShareFile({
    required MediaResource resource,
    required String password,
    required String stoken,
  }) async {
    final directories = <String>['0'];
    final seenDirectories = <String>{'0'};
    var requests = 0;
    while (directories.isNotEmpty && requests < 50) {
      final folder = directories.removeAt(0);
      var page = 1;
      while (page <= 20 && requests < 50) {
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
        _ensureSuccess(response, fallback: QuarkFailureKind.protocol, stage: 'share-detail');
        final rows = response.data['list'];
        if (rows is! List) break;
        for (final raw in rows) {
          if (raw is! Map) continue;
          final row = raw.cast<String, dynamic>();
          final fid = row['fid']?.toString() ?? '';
          final name = row['file_name']?.toString() ?? '';
          final isDirectory = row['dir'] == true || row['dir'] == 1;
          if (isDirectory) {
            if (fid.isNotEmpty && seenDirectories.add(fid) && seenDirectories.length <= 160) {
              directories.add(fid);
            }
            continue;
          }
          final size = int.tryParse(row['size']?.toString() ?? '') ?? 0;
          final sizeMatches = size == 0 || resource.sizeBytes == 0 || size == resource.sizeBytes;
          final idMatches = fid == resource.fileId;
          final fallbackNameMatches =
              resource.fileId.isEmpty && name == resource.fileName && sizeMatches;
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
        final total = metadata is Map ? int.tryParse(metadata['_total']?.toString() ?? '') : null;
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

  Future<String> _ensureStagingFolder() async {
    if (_stagingFolderId != null) return _stagingFolderId!;
    final response = await _request(
      'GET',
      'file/sort',
      params: const {
        'pdir_fid': '0',
        '_page': '1',
        '_size': '100',
        '_fetch_total': '1',
      },
    );
    _ensureSuccess(response, fallback: QuarkFailureKind.authExpired, stage: 'folder-list');
    final rows = response.data['list'];
    if (rows is List) {
      for (final raw in rows) {
        if (raw is! Map) continue;
        final row = raw.cast<String, dynamic>();
        final isDirectory = row['dir'] == true || row['dir'] == 1;
        if (isDirectory && row['file_name'] == _stagingFolderName) {
          final id = row['fid']?.toString() ?? '';
          if (id.isNotEmpty) {
            _stagingFolderId = id;
            return id;
          }
        }
      }
    }
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
    _ensureSuccess(create, fallback: QuarkFailureKind.saveFailed, stage: 'folder-create');
    final id = create.data['fid']?.toString() ?? '';
    if (id.isEmpty) {
      throw const QuarkException(
        QuarkFailureKind.saveFailed,
        'folder fid missing',
        stage: 'folder-create',
      );
    }
    _stagingFolderId = id;
    return id;
  }

  Future<String> _saveToStaging({
    required MediaResource resource,
    required String stoken,
    required String folderId,
    required _ShareFile shareFile,
  }) async {
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
    _ensureSuccess(response, fallback: QuarkFailureKind.saveFailed, stage: 'save');
    final data = response.data;
    final saveAs = data['save_as'] ??
        (data['task_resp'] is Map ? (data['task_resp'] as Map)['save_as'] : null) ??
        (data['task_resp'] is Map && (data['task_resp'] as Map)['data'] is Map
            ? ((data['task_resp'] as Map)['data'] as Map)['save_as']
            : null);
    String? fid;
    if (saveAs is Map) {
      final values = saveAs['save_as_select_top_fids'] ?? saveAs['save_as_top_fids'];
      if (values is List && values.isNotEmpty) fid = values.first?.toString();
      if (fid == null) {
        final firstVideo = saveAs['first_video'];
        if (firstVideo is Map) fid = firstVideo['fid']?.toString();
      }
      fid ??= saveAs['fid']?.toString();
    }
    final taskId = data['task_id']?.toString() ?? '';
    if ((fid == null || fid.isEmpty) && taskId.isNotEmpty) {
      var done = false;
      for (var attempt = 0; attempt < 30; attempt++) {
        final task = await _request(
          'GET',
          'task',
          params: {'task_id': taskId, 'retry_index': '$attempt'},
        );
        _ensureSuccess(task, fallback: QuarkFailureKind.saveFailed, stage: 'save-task');
        final status = task.data['status'];
        if (status == 2) {
          done = true;
          break;
        }
        if (status == 3) break;
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
      if (!done) {
        throw const QuarkException(
          QuarkFailureKind.saveFailed,
          'save task timeout',
          stage: 'save-task',
        );
      }
    }
    fid ??= await _recentSavedFid(folderId, shareFile.name);
    if (fid == null || fid.isEmpty) {
      throw const QuarkException(
        QuarkFailureKind.saveFailed,
        'saved fid missing',
        stage: 'save',
      );
    }
    return fid;
  }

  Future<String?> _recentSavedFid(String folderId, String name) async {
    final response = await _request(
      'GET',
      'file/sort',
      params: {
        'pdir_fid': folderId,
        '_page': '1',
        '_size': '100',
        '_fetch_total': '1',
        '_sort': 'created_at:desc',
      },
    );
    _ensureSuccess(response, fallback: QuarkFailureKind.saveFailed, stage: 'saved-lookup');
    final rows = response.data['list'];
    if (rows is! List) return null;
    for (final raw in rows) {
      if (raw is! Map) continue;
      final row = raw.cast<String, dynamic>();
      if (row['file_name'] == name && row['dir'] != true && row['dir'] != 1) {
        return row['fid']?.toString();
      }
    }
    return null;
  }

  Future<Uri?> _downloadUrl(String fid) async {
    for (final desktop in [false, true]) {
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
      if ((response.status == 401) || response.code == 31001) {
        throw const QuarkException(
          QuarkFailureKind.authExpired,
          'download session rejected',
          stage: 'download-url',
        );
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

  Future<void> _releaseFid(String fid, {bool suppress = false}) async {
    try {
      final response = await _request(
        'POST',
        'file/delete',
        body: {
          'action_type': 1,
          'filelist': [fid],
          'exclude_fids': [],
        },
      );
      final ok = response.code == 0 || response.code == 23004;
      if (!ok) {
        throw QuarkException(
          QuarkFailureKind.cleanupFailed,
          response.message,
          code: response.code,
          statusCode: response.status,
          stage: 'cleanup',
        );
      }
      await _ledgerRemove(fid);
      AppLog.info('quark-playback', 'temp-file-released');
    } catch (error) {
      AppLog.error('quark-playback', error);
      if (!suppress) rethrow;
    }
  }

  Future<void> cleanupStale() async {
    final entries = await _ledgerRead();
    if (entries.isEmpty) return;
    if (!await hasAccount) return;
    for (final entry in entries) {
      final fid = entry['fid']?.toString() ?? '';
      final createdAt = int.tryParse(entry['createdAt']?.toString() ?? '') ?? 0;
      if (fid.isEmpty) continue;
      if (DateTime.now().millisecondsSinceEpoch - createdAt < 10 * 60 * 1000) continue;
      await _releaseFid(fid, suppress: true);
    }
  }

  Future<List<Map<String, dynamic>>> _ledgerRead() async {
    try {
      if (!await _ledgerFile.exists()) return const [];
      final value = jsonDecode(await _ledgerFile.readAsString());
      if (value is! List) return const [];
      return value.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _ledgerWrite(List<Map<String, dynamic>> entries) async {
    await _ledgerFile.parent.create(recursive: true);
    await _ledgerFile.writeAsString(jsonEncode(entries), flush: true);
  }

  Future<void> _ledgerAdd(String fid, String folderId, String resourceId) async {
    final entries = await _ledgerRead();
    entries.removeWhere((entry) => entry['fid'] == fid);
    entries.add({
      'fid': fid,
      'folderId': folderId,
      'resourceId': resourceId,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    if (entries.length > 20) entries.removeRange(0, entries.length - 20);
    await _ledgerWrite(entries);
  }

  Future<void> _ledgerRemove(String fid) async {
    final entries = await _ledgerRead();
    entries.removeWhere((entry) => entry['fid'] == fid);
    await _ledgerWrite(entries);
  }

  void close() => _client.close();
}
