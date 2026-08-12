import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/migrations/migration_v38.dart';

void main() {
  sqfliteFfiInit();

  test(
    'V37 para V38 preserva dados e libera código comercial repetido',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('PRAGMA foreign_keys=ON');
      await _createV37Fixture(db);

      await db.insert('consignacoes', {
        'id': 'cons-37',
        'comercio_id': 'business-1',
        'fornecedor_id': 'supplier-1',
        'lote_colecao': 'Remessa legada',
        'recebida_em': '2026-07-01T10:00:00Z',
        'status': 'aberta',
        'criado_em': '2026-07-01T10:00:00Z',
      });
      await db.insert('pecas_unicas', {
        'id': 'piece-37',
        'comercio_id': 'business-1',
        'codigo_exclusivo': '516205',
        'nome': 'Anel legado',
        'descricao': 'Prata',
        'material': 'Prata',
        'fornecedor_id': 'supplier-1',
        'custo': 40.0,
        'preco': 62.0,
        'lote_id': 'cons-37',
        'cliente_id': 'client-1',
        'profissional_vendedor_id': 'user-1',
        'data_venda': '2026-07-03T10:00:00Z',
        'status': 'vendida',
        'data_cadastro': '2026-07-01T10:00:00Z',
      });
      await db.insert('consignacao_eventos', {
        'id': 'event-37',
        'comercio_id': 'business-1',
        'consignacao_id': 'cons-37',
        'peca_id': 'piece-37',
        'tipo': 'venda',
        'quantidade': 1,
        'valor': 62.0,
        'cliente_id': 'client-1',
        'criado_em': '2026-07-03T10:00:00Z',
      });
      await db.insert('pdv_vendas', {
        'id': 'sale-37',
        'comercio_id': 'business-1',
        'profissional_id': 'user-1',
        'cliente_id': 'client-1',
        'valor_total': 62.0,
        'data_venda': '2026-07-03T10:00:00Z',
        'status': 'concluida',
      });

      await expectLater(
        db.insert('pecas_unicas', {
          'id': 'blocked-before-v38',
          'comercio_id': 'business-1',
          'codigo_exclusivo': '516205',
          'nome': 'Código repetido',
          'preco': 62.0,
          'data_cadastro': '2026-07-01T10:00:00Z',
        }),
        throwsA(isA<DatabaseException>()),
      );

      await MigrationV38.executar(db);

      final piece = (await db.query(
        'pecas_unicas',
        where: 'id=?',
        whereArgs: ['piece-37'],
      )).single;
      expect(piece['codigo_exclusivo'], '516205');
      expect(piece['lote_id'], 'cons-37');
      expect(piece['cliente_id'], 'client-1');
      expect(piece['custo'], 40.0);
      expect(piece['preco'], 62.0);
      expect(piece['status'], 'vendida');
      expect(await db.query('consignacoes'), hasLength(1));
      expect((await db.query('consignacoes')).single['id'], 'cons-37');
      expect(await db.query('consignacao_eventos'), hasLength(1));
      expect(
        (await db.query('consignacao_eventos')).single['peca_id'],
        'piece-37',
      );
      expect(await db.query('pdv_vendas'), hasLength(1));
      expect((await db.query('pdv_vendas')).single['cliente_id'], 'client-1');

      final columns = (await db.rawQuery(
        'PRAGMA table_info(consignacoes)',
      )).map((row) => row['name']).toSet();
      expect(
        columns,
        containsAll(<String>[
          'contrato',
          'numero_mostruario',
          'data_pagamento',
          'observacoes',
          'arquivo_origem',
        ]),
      );

      await db.insert('pecas_unicas', {
        'id': 'piece-38-second',
        'comercio_id': 'business-1',
        'codigo_exclusivo': '516205',
        'nome': 'Segundo anel físico',
        'preco': 62.0,
        'lote_id': 'cons-37',
        'status': 'disponivel',
        'data_cadastro': '2026-07-01T10:00:00Z',
      });
      final repeated = await db.query(
        'pecas_unicas',
        where: 'comercio_id=? AND codigo_exclusivo=?',
        whereArgs: ['business-1', '516205'],
      );
      expect(repeated, hasLength(2));
      expect(repeated.map((row) => row['id']).toSet(), {
        'piece-37',
        'piece-38-second',
      });

      // Segunda abertura/aplicação é idempotente.
      await MigrationV38.executar(db);
      expect(await db.query('pecas_unicas'), hasLength(2));
      expect(await db.query('consignacao_eventos'), hasLength(1));
    },
  );
}

Future<void> _createV37Fixture(Database db) async {
  await db.execute('''CREATE TABLE consignacoes (
    id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, fornecedor_id TEXT NOT NULL,
    lote_colecao TEXT, recebida_em TEXT NOT NULL, fechamento_previsto TEXT,
    fechada_em TEXT, status TEXT NOT NULL DEFAULT 'aberta', criado_em TEXT NOT NULL
  )''');
  await db.execute('''CREATE TABLE pecas_unicas (
    id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL,
    codigo_exclusivo TEXT NOT NULL, nome TEXT NOT NULL, descricao TEXT,
    material TEXT, marca TEXT, fornecedor_id TEXT, custo REAL NOT NULL DEFAULT 0,
    preco REAL NOT NULL, lote_id TEXT, unidade_id TEXT, localizacao TEXT,
    cliente_id TEXT, profissional_vendedor_id TEXT, comissao REAL,
    data_venda TEXT, status TEXT NOT NULL DEFAULT 'disponivel',
    data_cadastro TEXT NOT NULL, UNIQUE(comercio_id, codigo_exclusivo)
  )''');
  await db.execute('''CREATE TABLE consignacao_eventos (
    id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, consignacao_id TEXT NOT NULL,
    peca_id TEXT, produto_id TEXT, tipo TEXT NOT NULL,
    quantidade REAL NOT NULL DEFAULT 1, valor REAL, cliente_id TEXT,
    profissional_id TEXT, observacoes TEXT, criado_em TEXT NOT NULL,
    FOREIGN KEY(consignacao_id) REFERENCES consignacoes(id) ON DELETE RESTRICT
  )''');
  await db.execute('''CREATE TABLE pdv_vendas (
    id TEXT PRIMARY KEY, comercio_id TEXT NOT NULL, unidade_id TEXT,
    profissional_id TEXT NOT NULL, cliente_id TEXT, valor_total REAL NOT NULL,
    data_venda TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'concluida'
  )''');
}
