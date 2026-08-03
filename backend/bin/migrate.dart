import 'dart:io';

import 'package:postgres/postgres.dart';

import 'package:studioflow_backend/src/database_config.dart';

Future<void> main() async {
  final databaseUrl = Platform.environment['DATABASE_URL']?.trim();
  if (databaseUrl == null || databaseUrl.isEmpty) {
    stderr.writeln('Defina DATABASE_URL antes de executar as migraÃ§Ãµes.');
    exitCode = 64;
    return;
  }

  final connection = await DatabaseConfig.createConnection(databaseUrl);
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
        stdout.writeln('MigraÃ§Ã£o $name jÃ¡ aplicada.');
        continue;
      }
      stdout.writeln('Aplicando $name...');
      await connection.execute(
        await file.readAsString(),
        queryMode: QueryMode.simple,
      );
    }
    stdout.writeln('MigraÃ§Ãµes concluÃ­das.');
  } finally {
    await connection.close();
  }
}
