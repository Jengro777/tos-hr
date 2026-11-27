enum RemoteSyncMode { full, incremental }

class SyncApiExecution {
  const SyncApiExecution({
    required this.statusCode,
    required this.success,
    required this.message,
  });

  final int statusCode;
  final bool success;
  final String message;
}

abstract interface class SyncApiServer {
  Future<void> start();

  Future<void> close();

  bool get isRunning;

  String? get error;

  List<String> get fullUrls;

  List<String> get incrementalUrls;

  int get port;
}
