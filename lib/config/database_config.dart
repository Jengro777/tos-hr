class DatabaseConfig {
  const DatabaseConfig({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.database,
    this.useSSL = false,
    this.sslCaPem = '',
    this.connectTimeout = const Duration(seconds: 15),
    this.proxyEnabled = false,
    this.remoteConfigured = false,
  });

  factory DatabaseConfig.fromEnvironment() {
    const host = String.fromEnvironment(
      'DB_HOST',
      defaultValue: String.fromEnvironment(
        'TIDB_HOST',
        defaultValue: String.fromEnvironment('DBCONF_HOST'),
      ),
    );
    const portText = String.fromEnvironment(
      'DB_PORT',
      defaultValue: String.fromEnvironment(
        'TIDB_PORT',
        defaultValue: String.fromEnvironment(
          'DBCONF_PORT',
          defaultValue: '4000',
        ),
      ),
    );
    const username = String.fromEnvironment(
      'DB_USERNAME',
      defaultValue: String.fromEnvironment(
        'TIDB_USERNAME',
        defaultValue: String.fromEnvironment('DBCONF_USERNAME'),
      ),
    );
    const password = String.fromEnvironment(
      'DB_PASSWORD',
      defaultValue: String.fromEnvironment(
        'TIDB_PASSWORD',
        defaultValue: String.fromEnvironment('DBCONF_PASSWORD'),
      ),
    );
    const database = String.fromEnvironment(
      'DB_DATABASE',
      defaultValue: String.fromEnvironment(
        'TIDB_DATABASE',
        defaultValue: String.fromEnvironment('DBCONF_DBNAME'),
      ),
    );
    const sslText = String.fromEnvironment(
      'DB_SSL_VERIFY',
      defaultValue: String.fromEnvironment(
        'TIDB_SSL_VERIFY',
        defaultValue: String.fromEnvironment(
          'DBCONF_SSL_VERIFY',
          defaultValue: 'true',
        ),
      ),
    );
    const sslCaPem = String.fromEnvironment(
      'DB_SSL_CA_PEM',
      defaultValue: String.fromEnvironment('TIDB_SSL_CA_PEM'),
    );
    return DatabaseConfig(
      host: host,
      port: int.tryParse(portText) ?? 4000,
      username: username,
      password: password,
      database: database,
      useSSL: sslText.toLowerCase() == 'true',
      sslCaPem: sslCaPem,
    );
  }

  final String host;
  final int port;
  final String username;
  final String password;
  final String database;
  final bool useSSL;
  final String sslCaPem;
  final Duration connectTimeout;
  final bool proxyEnabled;
  final bool remoteConfigured;

  bool get isConfigured => proxyEnabled
      ? remoteConfigured
      : _isRealValue(host) &&
            _isRealValue(username) &&
            password.isNotEmpty &&
            !password.startsWith('请填写') &&
            _isRealValue(database);

  List<String> get missingFields => proxyEnabled
      ? const []
      : [
          if (!_isRealValue(host)) 'DB_HOST',
          if (!_isRealValue(username)) 'DB_USERNAME',
          if (password.isEmpty || password.startsWith('请填写')) 'DB_PASSWORD',
          if (!_isRealValue(database)) 'DB_DATABASE',
        ];

  static bool _isRealValue(String value) {
    final normalized = value.trim();
    return normalized.isNotEmpty && !normalized.startsWith('请填写');
  }
}
