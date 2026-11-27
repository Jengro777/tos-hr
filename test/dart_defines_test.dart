import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/dart_defines.dart';

void main() {
  test('converts one local YAML file into Flutter dart defines', () async {
    final directory = await Directory.systemTemp.createTemp('tospino_hr_');
    addTearDown(() => directory.delete(recursive: true));
    final input = File('${directory.path}/app.local.yaml');
    final output = File('${directory.path}/defines.json');
    final caFile = File('${directory.path}/client-cert.pem');
    await caFile.writeAsString('-----BEGIN CERTIFICATE-----\ntest\n');
    await input.writeAsString('''
wecom:
  corp_id: ww-test
  agent_id: "1000012"
  secret: app-secret
database:
  host: tidb.example.com
  port: 4000
  username: root
  password: db-secret
  database: tospino_hr
  ssl_verify: true
  ssl_ca_file: client-cert.pem
''');

    await convertYamlConfig(input: input, output: output);
    final values = jsonDecode(await output.readAsString()) as Map;

    expect(values['WECOM_CORP_ID'], 'ww-test');
    expect(values['WECOM_CONTACT_SECRET'], '');
    expect(values['DB_HOST'], 'tidb.example.com');
    expect(values['DB_PORT'], '4000');
    expect(values['DB_SSL_VERIFY'], 'true');
    expect(values['DB_SSL_CA_PEM'], '-----BEGIN CERTIFICATE-----\ntest\n');
    expect(values.keys, isNot(contains('SYNC_API_ENABLED')));
    expect(values.keys, isNot(contains('SYNC_API_TOKEN')));
  });
}
