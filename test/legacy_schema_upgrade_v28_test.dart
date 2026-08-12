import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/core/constants/database_constants.dart';
import 'package:studioflow/database/database_service.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'database_schema_v28_fixture.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await DatabaseService.instance.fecharBanco();
  });

  test(
    'Deve sobreviver ao upgrade da v28 para v40+ (crash real do migracao_cardapio)',
    () async {
      final dbPath = await databaseFactory.getDatabasesPath();
      final path = join(dbPath, DatabaseConstants.nomeArquivo);
      await databaseFactory.deleteDatabase(path);

      // Cria banco V28 onde business_id NÃO existe estruturalmente, mas a versão é 28
      final dbLegado = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 28,
          onCreate: (db, version) async {
            // Cria toda a estrutura histórica exatamente como era
            await DatabaseSchemaV1Fixture.criar(db, 1);
            // Executa todas as migrations até a V28
            await DatabaseSchemaLatest.migrar(db, 1, 28);

            // Insere dados de cardápio (que forçam a MigrationV29 a tentar migrá-los para o estoque)
            await db.insert('cardapio_itens', {
              'id': 'item_1',
              'comercio_id': 'comercio_legado',
              'nome': 'Corte',
              'preco': 50.0,
              'categoria': 'Servicos',
              'ativo': 1,
              'criado_em': DateTime.now().toIso8601String(),
              'atualizado_em': DateTime.now().toIso8601String(),
            });
          },
        ),
      );
      await dbLegado.close();

      debugPrint(
        'BOOT 01 - banco fechado na v28. Iniciando DatabaseService...',
      );

      try {
        final db = await DatabaseService.instance.database;
        debugPrint('BOOT 05 - Banco aberto com sucesso pelo app!');
        final colunas = await db.rawQuery('PRAGMA table_info(estoque)');

        // Valida que a coluna business_id foi adicionada (Migration V36)
        expect(colunas.any((c) => c['name'] == 'business_id'), true);

        // Valida que o item legado do cardápio foi migrado corretamente (Migration V29)
        final estoqueMigrado = await db.query(
          'estoque',
          where: 'id = ?',
          whereArgs: ['item_1'],
        );
        expect(estoqueMigrado.length, 1);
        expect(estoqueMigrado.first['origem_catalogo'], 'migracao_cardapio');
        expect(estoqueMigrado.first['nome'], 'Corte');

        // Valida inserção moderna em estoque (schema completo + verifier atuou)
        await db.insert('estoque', {
          'id': 'estoque_novo_1',
          'business_id': 'business_123',
          'nome': 'Pomada Nova',
          'categoria': 'Produtos',
          'tipo': 'venda',
          'quantidade_atual': 10.0,
          'unidade': 'un',
          'ativo': 1,
          'data_cadastro': DateTime.now().toIso8601String(),
        });

        final estoqueNovo = await db.query(
          'estoque',
          where: 'id = ?',
          whereArgs: ['estoque_novo_1'],
        );
        expect(estoqueNovo.length, 1);
        expect(estoqueNovo.first['business_id'], 'business_123');

        // Valida reabertura (segunda inicialização)
        await DatabaseService.instance.fecharBanco();
        final dbReaberto = await DatabaseService.instance.database;
        final dadosReabertos = await dbReaberto.query(
          'estoque',
          where: 'id = ?',
          whereArgs: ['item_1'],
        );
        expect(dadosReabertos.length, 1);
      } catch (e) {
        debugPrint('CRASH REPRODUZIDO: \$e');
        rethrow;
      }
    },
  );
}
