import 'package:dartonic_core/dartonic_core.dart';
import 'package:mysql1/mysql1.dart';

class MysqlDartonicDriver implements DatabaseDriver {
  MysqlDartonicDriver(this.connection);

  final MySqlConnection connection;
  bool _transactionActive = false;

  @override
  Future<void> connect() async {
    await connection.query(
      "SET SESSION sql_mode = CONCAT(@@SESSION.sql_mode, ',ANSI_QUOTES')",
    );
  }

  @override
  Future<void> raw(String query, [List<Object?>? parameters]) async {
    await connection.query(query, parameters);
  }

  @override
  Future<RawQueryResult> execute(
    String query, [
    List<Object?>? parameters,
  ]) async {
    final result = await connection.query(query, parameters);
    return result
        .map(
          (row) => <String, Object?>{
            for (final entry in row.toColumnMap().entries)
              entry.key: entry.value,
          },
        )
        .toList(growable: false);
  }

  @override
  Future<void> createTable(String table, Map<String, String> columns) async {
    final definitions = columns.entries
        .map(
          (entry) =>
              '`${entry.key}` ${entry.value.replaceAll('AUTOINCREMENT', 'AUTO_INCREMENT').replaceAll('AUTOGENERATE', '')}',
        )
        .join(', ');
    await raw('CREATE TABLE IF NOT EXISTS `$table` ($definitions)');
  }

  @override
  Future<void> beginTransaction() async {
    if (_transactionActive) {
      throw StateError('A transaction is already active');
    }
    await connection.query('BEGIN');
    _transactionActive = true;
  }

  @override
  Future<void> commitTransaction() async {
    try {
      await connection.query('COMMIT');
    } finally {
      _transactionActive = false;
    }
  }

  @override
  Future<void> rollbackTransaction() async {
    try {
      await connection.query('ROLLBACK');
    } finally {
      _transactionActive = false;
    }
  }

  @override
  Future<void> close() async {}
}
