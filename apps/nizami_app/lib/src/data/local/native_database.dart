import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'local_schema.dart';

Future<Database> openNizamiDatabase() async {
  final support = await getApplicationSupportDirectory();
  final directory = Directory(p.join(support.path, 'Qodynex', 'Nizami'));
  await directory.create(recursive: true);
  final database = sqlite3.open(p.join(directory.path, 'nizami.sqlite3'));
  database.execute('PRAGMA foreign_keys = ON');
  database.execute('PRAGMA journal_mode = WAL');
  database.execute('PRAGMA synchronous = FULL');
  for (final statement in localSchema) {
    database.execute(statement);
  }
  database.execute(
    'INSERT OR REPLACE INTO app_meta(key, value) VALUES (?, ?)',
    ['schema_version', '$localSchemaVersion'],
  );
  return database;
}
