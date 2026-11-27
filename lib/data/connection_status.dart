class ConnectionStatus {
  const ConnectionStatus({
    required this.connected,
    required this.message,
    required this.checkedAt,
    this.latency,
  });

  final bool connected;
  final String message;
  final DateTime checkedAt;
  final Duration? latency;

  String get latencyText {
    final value = latency;
    return value == null ? '--' : '${value.inMilliseconds} ms';
  }
}
