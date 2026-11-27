class WecomConfig {
  const WecomConfig({
    required this.corpId,
    required this.agentId,
    required this.secret,
    this.contactSecret = '',
    this.proxyEnabled = false,
    this.remoteConfigured = false,
    this.remoteContactConfigured = false,
  });

  factory WecomConfig.fromEnvironment() {
    return const WecomConfig(
      corpId: String.fromEnvironment('WECOM_CORP_ID'),
      agentId: String.fromEnvironment('WECOM_AGENT_ID'),
      secret: String.fromEnvironment('WECOM_SECRET'),
      contactSecret: String.fromEnvironment('WECOM_CONTACT_SECRET'),
    );
  }

  final String corpId;
  final String agentId;
  final String secret;
  final String contactSecret;
  final bool proxyEnabled;
  final bool remoteConfigured;
  final bool remoteContactConfigured;

  bool get isConfigured =>
      _isRealValue(corpId) &&
      _isRealValue(agentId) &&
      (proxyEnabled ? remoteConfigured : _isRealValue(secret));

  bool get isContactConfigured =>
      _isRealValue(corpId) &&
      (proxyEnabled ? remoteContactConfigured : _isRealValue(contactSecret));

  bool get hasCheckinSecret =>
      proxyEnabled ? remoteConfigured : _isRealValue(secret);

  bool get hasContactSecret =>
      proxyEnabled ? remoteContactConfigured : _isRealValue(contactSecret);

  List<String> get missingFields {
    return [
      if (!_isRealValue(corpId)) '企业ID',
      if (!_isRealValue(agentId)) 'AgentId',
      if (!hasCheckinSecret) 'Secret',
      if (!hasContactSecret) '通讯录同步Secret',
    ];
  }

  List<String> get missingCheckinFields {
    return [
      if (!_isRealValue(corpId)) '企业ID',
      if (!_isRealValue(agentId)) 'AgentId',
      if (!hasCheckinSecret) 'Secret',
    ];
  }

  String get maskedCorpId => _mask(corpId);
  String get maskedAgentId => _mask(agentId);

  static bool _isRealValue(String value) {
    final normalized = value.trim();
    return normalized.isNotEmpty && !normalized.startsWith('请填写');
  }

  static String _mask(String value) {
    final normalized = value.trim();
    if (normalized.length <= 4) {
      return normalized.isEmpty ? '未配置' : '****';
    }
    final visibleLength = normalized.length >= 10 ? 4 : 2;
    return '${normalized.substring(0, visibleLength)}****'
        '${normalized.substring(normalized.length - visibleLength)}';
  }
}
