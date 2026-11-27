import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_runtime_config.dart';
import 'database_config.dart';
import 'sync_api_config.dart';
import 'wecom_config.dart';

Future<AppRuntimeConfig> loadCloudflareRuntimeConfig() async {
  final endpoint = Uri.base.resolve('/api/runtime-config');
  try {
    final response = await http
        .get(endpoint)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FormatException('Cloudflare API 返回 HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const FormatException('Cloudflare API 响应不是对象');
    }
    final wecom = _map(decoded['wecom']);
    final database = _map(decoded['database']);
    return AppRuntimeConfig(
      wecom: WecomConfig(
        corpId: _text(wecom['corpId']),
        agentId: _text(wecom['agentId']),
        secret: '',
        proxyEnabled: true,
        remoteConfigured: wecom['configured'] == true,
        remoteContactConfigured: wecom['contactConfigured'] == true,
      ),
      database: DatabaseConfig(
        host: _text(database['host']),
        port: int.tryParse(_text(database['port'])) ?? 4000,
        username: '',
        password: '',
        database: _text(database['database']),
        proxyEnabled: true,
        remoteConfigured: database['configured'] == true,
      ),
      syncApi: const SyncApiConfig(),
    );
  } catch (_) {
    return const AppRuntimeConfig(
      wecom: WecomConfig(
        corpId: '',
        agentId: '',
        secret: '',
        proxyEnabled: true,
      ),
      database: DatabaseConfig(
        host: '',
        port: 4000,
        username: '',
        password: '',
        database: '',
        proxyEnabled: true,
      ),
      syncApi: SyncApiConfig(),
    );
  }
}

Map _map(Object? value) => value is Map ? value : const <String, Object?>{};

String _text(Object? value) => value?.toString().trim() ?? '';
