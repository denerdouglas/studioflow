import 'package:sqflite/sqflite.dart';

abstract final class MigrationV47 {
  static Future<void> executar(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notificacoes (
        id TEXT PRIMARY KEY,
        tipo TEXT NOT NULL,
        titulo TEXT NOT NULL,
        mensagem TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pendente',
        data_criacao TEXT NOT NULL,
        data_agendada TEXT,
        data_envio TEXT,
        referencia_id TEXT
      )
    ''');
    final notificationColumns = (await db.rawQuery(
      'PRAGMA table_info(notificacoes)',
    )).map((row) => row['name']).toSet();
    for (final entry in const <String, String>{
      'comercio_id': 'TEXT',
      'entidade': 'TEXT',
      'prioridade': "TEXT NOT NULL DEFAULT 'normal'",
      'canal': "TEXT NOT NULL DEFAULT 'interna'",
      'rota': 'TEXT',
      'read_at': 'TEXT',
      'canceled_at': 'TEXT',
      'idempotency_key': 'TEXT',
    }.entries) {
      if (!notificationColumns.contains(entry.key)) {
        await db.execute(
          'ALTER TABLE notificacoes ADD COLUMN ${entry.key} ${entry.value}',
        );
      }
    }
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_notificacoes_idempotency
      ON notificacoes(comercio_id, idempotency_key)
      WHERE idempotency_key IS NOT NULL
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_notificacoes_comercio_status
      ON notificacoes(comercio_id, status, data_agendada)
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notification_preferences (
        id TEXT NOT NULL,
        business_id TEXT NOT NULL,
        category TEXT NOT NULL,
        channel TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (business_id, category, channel)
      )
    ''');
    final preferenceColumns = (await db.rawQuery(
      'PRAGMA table_info(notification_preferences)',
    )).map((row) => row['name']).toSet();
    if (!preferenceColumns.contains('id')) {
      await db.execute(
        'ALTER TABLE notification_preferences ADD COLUMN id TEXT',
      );
      await db.execute(
        "UPDATE notification_preferences SET id = category || ':' || channel WHERE id IS NULL",
      );
    }
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_notification_preferences_id
      ON notification_preferences(business_id, id)
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS accounts_payable (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        description TEXT NOT NULL,
        category TEXT NOT NULL,
        supplier TEXT,
        amount REAL NOT NULL CHECK(amount > 0),
        type TEXT NOT NULL CHECK(type IN ('fixa','variavel')),
        due_date TEXT NOT NULL,
        recurrence TEXT NOT NULL DEFAULT 'nenhuma',
        status TEXT NOT NULL DEFAULT 'pendente'
          CHECK(status IN ('pendente','paga','vencida','cancelada')),
        paid_at TEXT,
        payment_method TEXT,
        notes TEXT,
        receipt_uri TEXT,
        series_id TEXT,
        occurrence_key TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE (business_id, occurrence_key)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_accounts_payable_business_due
      ON accounts_payable(business_id, due_date, status)
    ''');
  }
}
