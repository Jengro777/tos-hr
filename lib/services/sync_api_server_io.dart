import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/sync_api_config.dart';
import 'sync_api_common.dart';

typedef RemoteSyncHandler =
    Future<SyncApiExecution> Function(RemoteSyncMode mode);

class HttpSyncApiServer implements SyncApiServer {
  HttpSyncApiServer({required this.config, required this.onSync});

  final SyncApiConfig config;
  final RemoteSyncHandler onSync;
  HttpServer? _server;
  String? _error;
  List<String> _hosts = const ['127.0.0.1', 'localhost'];

  @override
  bool get isRunning => _server != null;

  @override
  String? get error => _error;

  @override
  int get port => _server?.port ?? config.port;

  @override
  List<String> get fullUrls => _urls('/api/attendance/sync/full');

  @override
  List<String> get incrementalUrls => _urls('/api/attendance/sync/incremental');

  @override
  Future<void> start() async {
    if (!config.enabled) {
      return;
    }
    if (!config.isReady) {
      _error = '同步 API 未启动：SYNC_API_TOKEN 未配置';
      return;
    }
    try {
      final server = await HttpServer.bind(config.host, config.port);
      _server = server;
      _error = null;
      if (config.host == '0.0.0.0' || config.host == '::') {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
        );
        _hosts = {
          '127.0.0.1',
          'localhost',
          for (final interface in interfaces)
            for (final address in interface.addresses)
              if (!address.isLoopback) address.address,
        }.toList(growable: false);
      } else {
        _hosts = [config.host];
      }
      server.listen(
        _handleRequest,
        onError: (Object error) {
          _error = '同步 API 服务错误：$error';
        },
      );
    } catch (error) {
      _error = '同步 API 启动失败：$error';
    }
  }

  @override
  Future<void> close() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    _applyCors(request.response);
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }
    if (request.method != 'GET') {
      await _writeJson(request.response, HttpStatus.methodNotAllowed, {
        'success': false,
        'message': '仅支持 GET 请求',
      });
      return;
    }
    final providedToken =
        request.headers.value('x-api-token') ??
        request.uri.queryParameters['token'] ??
        '';
    if (!_constantTimeEquals(providedToken, config.token)) {
      await _writeJson(request.response, HttpStatus.unauthorized, {
        'success': false,
        'message': 'API Token 无效',
      });
      return;
    }
    final mode = switch (request.uri.path) {
      '/api/attendance/sync/full' => RemoteSyncMode.full,
      '/api/attendance/sync/incremental' => RemoteSyncMode.incremental,
      _ => null,
    };
    if (mode == null) {
      await _writeJson(request.response, HttpStatus.notFound, {
        'success': false,
        'message': '接口不存在',
      });
      return;
    }
    try {
      final result = await onSync(mode);
      await _writeJson(request.response, result.statusCode, {
        'success': result.success,
        'mode': mode.name,
        'message': result.message,
      });
    } catch (error) {
      await _writeJson(request.response, HttpStatus.internalServerError, {
        'success': false,
        'mode': mode.name,
        'message': '同步异常：$error',
      });
    }
  }

  List<String> _urls(String path) {
    final portValue = port;
    return [for (final host in _hosts) 'http://$host:$portValue$path'];
  }

  void _applyCors(HttpResponse response) {
    response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'X-Api-Token');
  }

  Future<void> _writeJson(
    HttpResponse response,
    int statusCode,
    Map<String, Object?> body,
  ) async {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }

  bool _constantTimeEquals(String left, String right) {
    final a = utf8.encode(left);
    final b = utf8.encode(right);
    var difference = a.length ^ b.length;
    final length = a.length > b.length ? a.length : b.length;
    for (var index = 0; index < length; index++) {
      final av = index < a.length ? a[index] : 0;
      final bv = index < b.length ? b[index] : 0;
      difference |= av ^ bv;
    }
    return difference == 0;
  }
}

SyncApiServer createSyncApiServer({
  required SyncApiConfig config,
  required RemoteSyncHandler onSync,
}) {
  return HttpSyncApiServer(config: config, onSync: onSync);
}
