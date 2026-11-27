import 'package:dartonic_core/dartonic_core.dart';
import 'package:sqflite_common/sqlite_api.dart' as sqlite_api;

class SqfliteDartonicDriver implements DatabaseDriver {
  SqfliteDartonicDriver(this._database);

  final sqlite_api.Database _database;
  bool _transactionActive = false;

  sqlite_api.DatabaseExecutor get _executor => _database;

  @override
  Future<void> connect() async {}

  @override
  Future<void> raw(String query, [List<Object?>? parameters]) async {
    await execute(query, parameters);
  }

  @override
  Future<RawQueryResult> execute(
    String query, [
    List<Object?>? parameters,
  ]) async {
    final normalized = query.trimLeft().toUpperCase();
    if (normalized.startsWith('SELECT') ||
        normalized.startsWith('WITH') ||
        normalized.startsWith('PRAGMA')) {
      return _executor.rawQuery(query, parameters);
    }
    if (normalized.startsWith('INSERT')) {
      await _executor.rawInsert(query, parameters);
      return const [];
    }
    if (normalized.startsWith('UPDATE')) {
      await _executor.rawUpdate(query, parameters);
      return const [];
    }
    if (normalized.startsWith('DELETE')) {
      await _executor.rawDelete(query, parameters);
      return const [];
    }
    await _executor.execute(query, parameters);
    return const [];
  }

  @override
  Future<void> createTable(String table, Map<String, String> columns) async {
    final definitions = columns.entries
        .map((entry) => '"${entry.key}" ${entry.value}')
        .join(', ');
    await raw('CREATE TABLE IF NOT EXISTS "$table" ($definitions)');
  }

  @override
  Future<void> beginTransaction() async {
    if (_transactionActive) {
      throw StateError('A transaction is already active');
    }
    await _database.execute('BEGIN IMMEDIATE');
    _transactionActive = true;
  }

  @override
  Future<void> commitTransaction() async {
    try {
      await _database.execute('COMMIT');
    } finally {
      _transactionActive = false;
    }
  }

  @override
  Future<void> rollbackTransaction() async {
    try {
      await _database.execute('ROLLBACK');
    } finally {
      _transactionActive = false;
    }
  }

  @override
  Future<void> close() async {}
}
