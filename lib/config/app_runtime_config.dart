import 'package:flutter/foundation.dart';
import 'package:yaml/yaml.dart';

import 'database_config.dart';
import 'cloudflare_runtime_config.dart';
import 'local_yaml_source.dart'
    if (dart.library.io) 'local_yaml_source_io.dart'
    as local_source;
import 'sync_api_config.dart';
import 'wecom_config.dart';

class AppRuntimeConfig {
  const AppRuntimeConfig({
    required this.wecom,
    required this.database,
    required this.syncApi,
  });

  final WecomConfig wecom;
  final DatabaseConfig database;
  final SyncApiConfig syncApi;
}

Future<AppRuntimeConfig> loadAppRuntimeConfig() async {
  if (kIsWeb) {
    return loadCloudflareRuntimeConfig();
  }
  final environment = _environmentConfig();
  if (!kDebugMode) {
    return environment;
  }
  final source = await local_source.loadLocalYamlSource();
  if (source == null) {
    return environment;
  }
  return _parseLocalYaml(source, environment);
}

AppRuntimeConfig _environmentConfig() {
  return AppRuntimeConfig(
    wecom: WecomConfig.fromEnvironment(),
    database: DatabaseConfig.fromEnvironment(),
    syncApi: SyncApiConfig.fromEnvironment(),
  );
}

Future<AppRuntimeConfig> _parseLocalYaml(
  local_source.LocalYamlSource source,
  AppRuntimeConfig fallback,
) async {
  final document = loadYaml(source.content);
  if (document is! Map) {
    throw const FormatException('config/app.local.yaml 根节点必须是对象');
  }
  final wecomNode = _map(document['wecom']);
  final databaseNode = _map(document['database']);
  final caPem = await _loadCaPem(
    databaseNode,
    baseDirectory: source.baseDirectory,
    fallback: fallback.database.sslCaPem,
  );
  return AppRuntimeConfig(
    wecom: WecomConfig(
      corpId: _text(wecomNode['corp_id']) ?? fallback.wecom.corpId,
      agentId: _text(wecomNode['agent_id']) ?? fallback.wecom.agentId,
      secret: _text(wecomNode['secret']) ?? fallback.wecom.secret,
      contactSecret:
          _text(wecomNode['contact_secret']) ?? fallback.wecom.contactSecret,
    ),
    database: DatabaseConfig(
      host: _text(databaseNode['host']) ?? fallback.database.host,
      port:
          int.tryParse(databaseNode['port']?.toString() ?? '') ??
          fallback.database.port,
      username: _text(databaseNode['username']) ?? fallback.database.username,
      password: _text(databaseNode['password']) ?? fallback.database.password,
      database: _text(databaseNode['database']) ?? fallback.database.database,
      useSSL: _bool(databaseNode['ssl_verify']) ?? fallback.database.useSSL,
      sslCaPem: caPem,
    ),
    syncApi: fallback.syncApi,
  );
}

Future<String> _loadCaPem(
  Map database, {
  required String baseDirectory,
  required String fallback,
}) async {
  final path = _text(database['ssl_ca_file']);
  if (path == null) {
    return fallback;
  }
  final content = await local_source.readLocalTextFile(
    baseDirectory: baseDirectory,
    path: path,
  );
  if (content == null) {
    throw FormatException('数据库 CA 文件不存在：$path');
  }
  return content;
}

Map _map(Object? value) {
  return value is Map ? value : const {};
}

String? _text(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text.startsWith('请填写')) {
    return null;
  }
  return text;
}

bool? _bool(Object? value) {
  if (value is bool) {
    return value;
  }
  final text = value?.toString().toLowerCase();
  if (text == 'true') {
    return true;
  }
  if (text == 'false') {
    return false;
  }
  return null;
}
