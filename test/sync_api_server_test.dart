import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tospino_hr/config/sync_api_config.dart';
import 'package:tospino_hr/services/sync_api_server.dart';

void main() {
  test('exposes token-protected full and incremental GET endpoints', () async {
    final calls = <RemoteSyncMode>[];
    final server = createSyncApiServer(
      config: const SyncApiConfig(
        enabled: true,
        host: '127.0.0.1',
        port: 0,
        token: 'api-token',
      ),
      onSync: (mode) async {
        calls.add(mode);
        return SyncApiExecution(
          statusCode: 200,
          success: true,
          message: '${mode.name} 完成',
        );
      },
    );
    addTearDown(server.close);
    await server.start();

    expect(server.isRunning, isTrue);
    final full = await _get(server.fullUrls.first, token: 'api-token');
    final incremental = await _get(
      server.incrementalUrls.first,
      token: 'api-token',
    );
    final unauthorized = await _get(
      server.fullUrls.first,
      token: 'wrong-token',
    );

    expect(full.statusCode, 200);
    expect(incremental.statusCode, 200);
    expect(unauthorized.statusCode, 401);
    expect(calls, [RemoteSyncMode.full, RemoteSyncMode.incremental]);
  });
}

Future<({int statusCode, Map body})> _get(
  String url, {
  required String token,
}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set('X-Api-Token', token);
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    return (statusCode: response.statusCode, body: jsonDecode(text) as Map);
  } finally {
    client.close(force: true);
  }
}
