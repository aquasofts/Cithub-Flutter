import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

String localId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32).toRadixString(16)}';

final localDatabaseProvider = Provider<LocalDatabase>((ref) => LocalDatabase());
final localRevisionProvider = StateProvider<int>((ref) => 0);

class LocalDatabase {
  LocalDatabase();
  LocalDatabase.at({required this.path, this.factory});
  String? path;
  DatabaseFactory? factory;
  Future<Database>? _database;
  Future<Database> get database => _database ??= _open();
  Future<Database> _open() async => (factory ?? databaseFactory).openDatabase(
    path ?? '${await getDatabasesPath()}/cithub_local.db',
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE schedules (id TEXT PRIMARY KEY, revision INTEGER NOT NULL, body TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE schedule_versions (revision INTEGER PRIMARY KEY AUTOINCREMENT, schedule_id TEXT NOT NULL, body TEXT NOT NULL, summary TEXT NOT NULL, created_at TEXT NOT NULL, operation_id TEXT UNIQUE NOT NULL)',
        );
        await db.execute(
          'CREATE INDEX versions_schedule ON schedule_versions(schedule_id, revision)',
        );
        await db.execute(
          'CREATE TABLE conversations (id TEXT PRIMARY KEY, title TEXT NOT NULL, model TEXT NOT NULL, updated_at TEXT NOT NULL, messages TEXT NOT NULL)',
        );
      },
    ),
  );
  Future<String?> getMeta(String key) async {
    final rows = await (await database).query(
      'meta',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setMeta(String key, String value) async =>
      (await database).insert('meta', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
}
