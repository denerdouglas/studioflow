import 'dart:io';

import 'package:postgres/postgres.dart';

Future<void> main() async {
  final databaseUrl = Platform.environment['DATABASE_URL']?.trim();
  if (databaseUrl == null || databaseUrl.isEmpty) {
    stderr.writeln('Defina DATABASE_URL antes de executar as migrações.');
    exitCode = 64;
    return;
  }

  final connection = await Connection.openFromUrl(databaseUrl);
  try {
    final directory = Directory('migrations');
    final files =
        directory
            .listSync()
            .whereType<File>()
            .where(
              (file) =>
                  RegExp(r'^\d+_.+\.sql$').hasMatch(file.uri.pathSegments.last),
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      final version = int.parse(name.split('_').first);
      final tableExists = await connection.execute('''
        SELECT to_regclass('public.schema_migrations') IS NOT NULL
      ''');
      var applied = false;
      if (tableExists.single[0] == true) {
        final result = await connection.execute(
          Sql.named('SELECT 1 FROM schema_migrations WHERE version = @version'),
          parameters: {'version': version},
        );
        applied = result.isNotEmpty;
      }
      if (applied) {
        stdout.writeln('Migração $name já aplicada.');
        continue;
      }
      stdout.writeln('Aplicando $name...');
      await connection.execute(await file.readAsString());
    }
    stdout.writeln('Migrações concluídas.');
  } finally {
    await connection.close();
  }
}
