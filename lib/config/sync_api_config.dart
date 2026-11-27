class SyncApiConfig {
  const SyncApiConfig({
    this.enabled = false,
    this.host = '0.0.0.0',
    this.port = 9010,
    this.token = '',
  });

  factory SyncApiConfig.fromEnvironment() {
    const enabledText = String.fromEnvironment(
      'SYNC_API_ENABLED',
      defaultValue: 'false',
    );
    const host = String.fromEnvironment(
      'SYNC_API_HOST',
      defaultValue: '0.0.0.0',
    );
    const portText = String.fromEnvironment(
      'SYNC_API_PORT',
      defaultValue: '9010',
    );
    const token = String.fromEnvironment('SYNC_API_TOKEN');
    return SyncApiConfig(
      enabled: enabledText.toLowerCase() == 'true',
      host: host,
      port: int.tryParse(portText) ?? 9010,
      token: token,
    );
  }

  final bool enabled;
  final String host;
  final int port;
  final String token;

  bool get isReady =>
      enabled && token.trim().isNotEmpty && !token.trim().startsWith('请填写');
}
