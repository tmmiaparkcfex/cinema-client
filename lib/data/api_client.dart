import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/app_log.dart';
import '../core/app_models.dart';
import '../core/app_settings.dart';

enum ApiFailureKind { network, timeout, http, protocol, server }

class ApiException implements Exception {
  const ApiException(
    this.kind,
    this.message, {
    required this.endpoint,
    this.statusCode,
    this.code,
  });

  final ApiFailureKind kind;
  final String message;
  final String endpoint;
  final int? statusCode;
  final int? code;

  String get userMessage {
    switch (kind) {
      case ApiFailureKind.network:
        return '无法连接影视接口。请检查手机与服务器是否在同一网络，或到“我的”修改接口地址。';
      case ApiFailureKind.timeout:
        return '影视接口响应超时。服务器仍在运行，但本次请求没有及时完成，请重试。';
      case ApiFailureKind.http:
        return '影视接口返回异常（HTTP ${statusCode ?? '未知'}）。';
      case ApiFailureKind.protocol:
        return '影视接口返回的数据格式无法识别，可能需要更新客户端。';
      case ApiFailureKind.server:
        return message.isEmpty ? '影视接口拒绝了本次请求。' : message;
    }
  }

  @override
  String toString() => 'ApiException($kind, $endpoint, $statusCode, $code): $message';
}

class VodApi {
  VodApi({
    required this.settings,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  final AppSettings settings;
  final http.Client _client;
  final Duration timeout;

  void close() => _client.close();

  Uri _uri(String path, [Map<String, String> query = const {}]) {
    final base = settings.baseUrl.endsWith('/')
        ? settings.baseUrl.substring(0, settings.baseUrl.length - 1)
        : settings.baseUrl;
    return Uri.parse('$base$path').replace(queryParameters: query.isEmpty ? null : query);
  }

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, String> query = const {},
  }) async {
    final started = DateTime.now();
    final uri = _uri(path, query);
    try {
      final response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(timeout);
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      AppLog.info('api', 'GET $path status=${response.statusCode} ms=$elapsed bytes=${response.bodyBytes.length}');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          ApiFailureKind.http,
          'HTTP ${response.statusCode}',
          endpoint: path,
          statusCode: response.statusCode,
        );
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
      if (decoded is! Map<String, dynamic>) {
        throw ApiException(ApiFailureKind.protocol, '根节点不是对象', endpoint: path);
      }
      if (decoded['ok'] == false) {
        throw ApiException(
          ApiFailureKind.server,
          (decoded['error'] ?? decoded['msg'] ?? '').toString(),
          endpoint: path,
          statusCode: response.statusCode,
          code: decoded['code'] is num ? (decoded['code'] as num).toInt() : null,
        );
      }
      return decoded;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException(ApiFailureKind.timeout, '请求超时', endpoint: path);
    } on SocketException catch (error) {
      AppLog.error('api', error);
      throw ApiException(ApiFailureKind.network, error.message, endpoint: path);
    } on http.ClientException catch (error) {
      AppLog.error('api', error);
      throw ApiException(ApiFailureKind.network, error.message, endpoint: path);
    } on FormatException catch (error) {
      AppLog.error('api', error);
      throw ApiException(ApiFailureKind.protocol, error.message, endpoint: path);
    }
  }

  Future<HomeFeed> fetchHome() async {
    final json = await _getJson('/api/home');
    final feed = HomeFeed.fromJson(json);
    if (feed.all.isEmpty) {
      throw const ApiException(
        ApiFailureKind.server,
        '接口没有返回任何已核验作品',
        endpoint: '/api/home',
      );
    }
    return feed;
  }

  Future<CatalogPage> fetchList(MediaKind kind, {int page = 1}) async {
    final json = await _getJson(
      '/api/list',
      query: {'type': kind == MediaKind.tv ? 'tv' : 'movie', 'pg': '$page'},
    );
    return CatalogPage.fromJson(json);
  }

  Future<CatalogPage> search(String query, {int page = 1}) async {
    final value = query.trim();
    if (value.isEmpty) return const CatalogPage(items: [], total: 0, page: 1, pageCount: 1);
    final json = await _getJson('/api/search', query: {'wd': value, 'pg': '$page'});
    return CatalogPage.fromJson(json);
  }

  Future<VodDetail> fetchDetail(String id) async {
    final json = await _getJson('/api/detail', query: {'id': id});
    final detail = VodDetail.fromJson(json);
    if (detail.item.key.isEmpty) {
      throw const ApiException(
        ApiFailureKind.protocol,
        '详情缺少作品标识',
        endpoint: '/api/detail',
      );
    }
    return detail;
  }

  Future<MediaResource> fetchResource(String id) async {
    final json = await _getJson('/api/resource', query: {'id': id});
    final resource = json['resource'];
    if (resource is! Map) {
      throw const ApiException(
        ApiFailureKind.protocol,
        '资源响应缺少 resource',
        endpoint: '/api/resource',
      );
    }
    return MediaResource.fromJson(resource.cast<String, dynamic>());
  }
}
