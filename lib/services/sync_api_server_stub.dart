import '../config/sync_api_config.dart';
import 'sync_api_common.dart';

typedef RemoteSyncHandler =
    Future<SyncApiExecution> Function(RemoteSyncMode mode);

class UnsupportedSyncApiServer implements SyncApiServer {
  UnsupportedSyncApiServer({required this.config});

  final SyncApiConfig config;

  @override
  String? get error => config.enabled ? 'Web 端不支持启动本地同步 API 服务' : null;

  @override
  List<String> get fullUrls => const [];

  @override
  List<String> get incrementalUrls => const [];

  @override
  bool get isRunning => false;

  @override
  int get port => config.port;

  @override
  Future<void> close() async {}

  @override
  Future<void> start() async {}
}

SyncApiServer createSyncApiServer({
  required SyncApiConfig config,
  required RemoteSyncHandler onSync,
}) {
  return UnsupportedSyncApiServer(config: config);
}
