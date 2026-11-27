import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

Future<void> main(List<String> arguments) async {
  final inputPath = _option(arguments, '--input') ?? 'config/app.local.yaml';
  final outputPath =
      _option(arguments, '--output') ?? '.dart_tool/local_dart_defines.json';
  final input = File(inputPath);
  if (!await input.exists()) {
    stderr.writeln('配置文件不存在：$inputPath');
    exitCode = 2;
    return;
  }
  final output = File(outputPath);
  await convertYamlConfig(input: input, output: output);
  stdout.writeln('已生成 Flutter 配置：$outputPath');
}

Future<void> convertYamlConfig({
  required File input,
  required File output,
}) async {
  final source = await input.readAsString();
  final document = loadYaml(source);
  if (document is! Map) {
    throw const FormatException('YAML 根节点必须是对象');
  }
  final wecom = _map(document['wecom'], 'wecom');
  final database = _map(document['database'], 'database');
  final sslCaPem = await _readSslCa(
    configDirectory: input.parent,
    database: database,
  );
  final values = <String, Object>{
    'WECOM_CORP_ID': _required(wecom, 'corp_id', 'wecom.corp_id'),
    'WECOM_AGENT_ID': _required(wecom, 'agent_id', 'wecom.agent_id'),
    'WECOM_SECRET': _required(wecom, 'secret', 'wecom.secret'),
    'WECOM_CONTACT_SECRET': wecom['contact_secret']?.toString() ?? '',
    'DB_HOST': _required(database, 'host', 'database.host'),
    'DB_PORT': _required(database, 'port', 'database.port').toString(),
    'DB_USERNAME': _required(database, 'username', 'database.username'),
    'DB_PASSWORD': _required(database, 'password', 'database.password'),
    'DB_DATABASE': _required(database, 'database', 'database.database'),
    'DB_SSL_VERIFY': _required(
      database,
      'ssl_verify',
      'database.ssl_verify',
    ).toString(),
    'DB_SSL_CA_PEM': sslCaPem,
  };
  await output.parent.create(recursive: true);
  await output.writeAsString(
    const JsonEncoder.withIndent('  ').convert(values),
    flush: true,
  );
}

Future<String> _readSslCa({
  required Directory configDirectory,
  required Map database,
}) async {
  final configuredPath = database['ssl_ca_file']?.toString().trim() ?? '';
  if (configuredPath.isEmpty) {
    return '';
  }
  final file = path.isAbsolute(configuredPath)
      ? File(configuredPath)
      : File(path.join(configDirectory.path, configuredPath));
  if (!await file.exists()) {
    throw FormatException('SSL CA 文件不存在：${file.path}');
  }
  return file.readAsString();
}

Map _map(Object? value, String path) {
  if (value is! Map) {
    throw FormatException('$path 必须是对象');
  }
  return value;
}

Object _required(Map source, String key, String path) {
  final value = source[key];
  if (value == null || value.toString().trim().isEmpty) {
    throw FormatException('缺少配置项：$path');
  }
  return value is Map || value is List ? value : value as Object;
}

String? _option(List<String> arguments, String name) {
  for (final argument in arguments) {
    if (argument.startsWith('$name=')) {
      return argument.substring(name.length + 1);
    }
  }
  return null;
}
