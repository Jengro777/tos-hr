import 'package:flutter_test/flutter_test.dart';
import 'package:tospino_hr/config/database_config.dart';

void main() {
  test('rejects placeholder TiDB values', () {
    const config = DatabaseConfig(
      host: '请填写TiDB主机',
      port: 4000,
      username: '请填写TiDB用户名',
      password: '请填写TiDB密码',
      database: '请填写数据库名',
    );

    expect(config.isConfigured, isFalse);
    expect(config.missingFields, [
      'DB_HOST',
      'DB_USERNAME',
      'DB_PASSWORD',
      'DB_DATABASE',
    ]);
  });

  test('accepts complete TiDB settings', () {
    const config = DatabaseConfig(
      host: 'tidb.example.com',
      port: 4000,
      username: 'user',
      password: 'secret',
      database: 'tospino_hr',
      useSSL: true,
    );

    expect(config.isConfigured, isTrue);
    expect(config.missingFields, isEmpty);
  });
}
