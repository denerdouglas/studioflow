import 'package:sqflite/sqflite.dart';

abstract final class MigrationV41 {
  static Future<void> executar(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS accounts (
      id TEXT PRIMARY KEY, login TEXT NOT NULL UNIQUE, nome TEXT NOT NULL,
      telefone TEXT NOT NULL DEFAULT '', ativo INTEGER NOT NULL DEFAULT 1,
      senha_hash TEXT, senha_salt TEXT,
      criado_em TEXT NOT NULL, atualizado_em TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS business_memberships (
      id TEXT PRIMARY KEY, account_id TEXT NOT NULL, business_id TEXT NOT NULL,
      usuario_id TEXT, profissional_id TEXT, role TEXT NOT NULL,
      permissions_json TEXT NOT NULL DEFAULT '{}', status TEXT NOT NULL,
      principal INTEGER NOT NULL DEFAULT 0, criado_em TEXT NOT NULL,
      atualizado_em TEXT NOT NULL, UNIQUE(account_id,business_id))''');
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS business_membership_requests (
      id TEXT PRIMARY KEY, account_id TEXT NOT NULL, business_id TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending', solicitado_em TEXT NOT NULL,
      revisado_por_account_id TEXT, revisado_em TEXT,
      role_aprovada TEXT, permissions_json TEXT,
      observacao TEXT)''',
    );
    await _addColumn(db, 'accounts', 'senha_hash', 'TEXT');
    await _addColumn(db, 'accounts', 'senha_salt', 'TEXT');
    await _addColumn(
      db,
      'business_membership_requests',
      'role_aprovada',
      'TEXT',
    );
    await _addColumn(
      db,
      'business_membership_requests',
      'permissions_json',
      'TEXT',
    );
    await _addColumn(db, 'business_membership_requests', 'observacao', 'TEXT');
    await db.execute('''CREATE TABLE IF NOT EXISTS business_public_codes (
      id TEXT PRIMARY KEY, business_id TEXT NOT NULL, code TEXT NOT NULL UNIQUE,
      ativo INTEGER NOT NULL DEFAULT 1, criado_em TEXT NOT NULL,
      rotacionado_em TEXT)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS account_entitlements (
      account_id TEXT PRIMARY KEY, plan_id TEXT NOT NULL DEFAULT 'base',
      status TEXT NOT NULL DEFAULT 'inactive', unidades_incluidas INTEGER NOT NULL DEFAULT 1,
      unidades_contratadas INTEGER NOT NULL DEFAULT 1,
      colaboradores_incluidos INTEGER NOT NULL DEFAULT 3,
      capacidade_colaboradores INTEGER NOT NULL DEFAULT 3,
      preco_base REAL NOT NULL DEFAULT 0, versao INTEGER NOT NULL DEFAULT 1,
      valido_ate TEXT, atualizado_em TEXT NOT NULL)''');

    final now = DateTime.now().toUtc().toIso8601String();
    final users = await _tableExists(db, 'usuarios')
        ? await db.query('usuarios')
        : const <Map<String, Object?>>[];
    for (final user in users) {
      final login = (user['email_login'] as String).trim().toLowerCase();
      final accountId = 'acc_${_stable(login)}';
      await db.insert('accounts', {
        'id': accountId,
        'login': login,
        'nome': user['nome'],
        'telefone': user['telefone'] ?? '',
        'senha_hash': user['senha_hash'],
        'senha_salt': user['senha_salt'],
        'ativo': user['ativo'],
        'criado_em': user['criado_em'] ?? now,
        'atualizado_em': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      final role = switch (user['funcao']) {
        'dono' => 'owner',
        'gerente' => 'manager',
        _ => 'collaborator',
      };
      await db.insert('business_memberships', {
        'id': 'mem_${user['id']}',
        'account_id': accountId,
        'business_id': user['comercio_id'],
        'usuario_id': user['id'],
        'profissional_id': user['profissional_id'],
        'role': role,
        'status': (user['ativo'] as num? ?? 0) == 1 ? 'active' : 'inactive',
        'principal': role == 'owner' ? 1 : 0,
        'criado_em': user['criado_em'] ?? now,
        'atualizado_em': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    final businesses = await _tableExists(db, 'comercios')
        ? await db.query('comercios', columns: ['id'])
        : const <Map<String, Object?>>[];
    for (final business in businesses) {
      final id = business['id'] as String;
      await db.insert('business_public_codes', {
        'id': 'code_$id',
        'business_id': id,
        'code': 'SF-${_stable(id).substring(0, 6).toUpperCase()}',
        'ativo': 1,
        'criado_em': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    final managers =
        await _tableExists(db, 'permissoes_acoes') &&
            await _tableExists(db, 'usuarios')
        ? await db.query(
            'usuarios',
            columns: ['id', 'comercio_id'],
            where: 'funcao=? AND ativo=1',
            whereArgs: ['gerente'],
          )
        : const <Map<String, Object?>>[];
    for (final manager in managers) {
      await db.insert('permissoes_acoes', {
        'usuario_id': manager['id'],
        'comercio_id': manager['comercio_id'],
        'acao': 'agendaVerTodas',
        'permitido': 1,
        'atualizado_em': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    if (!await _tableExists(db, 'profissional_servicos')) return;
    await _addColumn(db, 'profissional_servicos', 'business_id', 'TEXT');
    await _addColumn(db, 'profissional_servicos', 'ativo', 'INTEGER DEFAULT 1');
    await _addColumn(
      db,
      'profissional_servicos',
      'comissao_percentual_override',
      'REAL',
    );
    await _addColumn(db, 'profissional_servicos', 'atualizado_por', 'TEXT');
    await _addColumn(db, 'profissional_servicos', 'criado_em', 'TEXT');
    await _addColumn(db, 'profissional_servicos', 'atualizado_em', 'TEXT');
    if (await _tableExists(db, 'profissionais')) {
      await db.execute('''UPDATE profissional_servicos SET business_id=(
      SELECT comercio_id FROM profissionais p
      WHERE p.id=profissional_servicos.profissional_id)
      WHERE business_id IS NULL''');
    }
  }

  static String _stable(String value) {
    var hash = 0x811c9dc5;
    for (final code in value.codeUnits) {
      hash ^= code;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static Future<void> _addColumn(
    DatabaseExecutor db,
    String table,
    String name,
    String type,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (!columns.any((column) => column['name'] == name)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $name $type');
    }
  }

  static Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
      [table],
    );
    return rows.isNotEmpty;
  }
}
