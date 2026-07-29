import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/repositories/acesso_repository.dart';
import 'package:studioflow/repositories/commercial_repository.dart';
import 'package:studioflow/services/product_lookup_service.dart';
import 'package:studioflow/services/session_controller.dart';

void main() {
  sqfliteFfiInit();

  group('Sprint 6 - base comercial', () {
    late Database db;
    late AcessoRepository access;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 6,
          onConfigure: (database) =>
              database.execute('PRAGMA foreign_keys = ON'),
          onCreate: DatabaseSchemaLatest.criar,
        ),
      );
      access = AcessoRepository(databaseProvider: () async => db);
    });

    tearDown(() async {
      await db.close();
    });

    test('cadastro cria trial de 30 dias e checklist isolado', () async {
      final owner = await _createCommerce(access, 'a');
      SessionController.instance.entrar(owner);
      final repository = CommercialRepository(databaseProvider: () async => db);

      final subscription = await repository.subscription();
      final steps = await repository.setupProgress();

      expect(subscription.status, SubscriptionStatus.trial);
      expect(subscription.monthlyPrice, 24.99);
      expect(subscription.trialDaysRemaining, inInclusiveRange(29, 30));
      expect(steps.length, 15);
      expect(steps['dados_negocio'], isTrue);
    });

    test('pagamento mock altera status sem dados de cartão', () async {
      final owner = await _createCommerce(access, 'pay');
      SessionController.instance.entrar(owner);
      final repository = CommercialRepository(databaseProvider: () async => db);

      final result = await repository.simulateSubscription();
      final columns = await db.rawQuery('PRAGMA table_info(assinaturas)');

      expect(result.status, SubscriptionStatus.active);
      expect(
        columns.map((row) => row['name']),
        isNot(contains('numero_cartao')),
      );
      expect(await db.query('assinatura_eventos'), hasLength(1));
    });

    test(
      'GTIN é normalizado, validado e providers respeitam prioridade',
      () async {
        const gtin = '7894900011517';
        expect(ProductLookupService.normalizeGtin('789 490001151-7'), gtin);
        expect(ProductLookupService.isValidGtin(gtin), isTrue);
        expect(ProductLookupService.isValidGtin('7894900011518'), isFalse);

        final product = CatalogProduct(
          gtin: gtin,
          name: 'Produto de teste',
          source: 'mock',
          confidence: 0.9,
        );
        final service = ProductLookupService(
          databaseProvider: () async => db,
          providers: [
            const MockProductCatalogProvider(),
            MockProductCatalogProvider({gtin: product}),
          ],
        );
        final result = await service.lookup(gtin, commerceId: 'com_test');

        expect(result.product?.name, 'Produto de teste');
        expect(result.consultedProviders, ['mock', 'mock']);
        final cached = await service.lookup(gtin, commerceId: 'com_test');
        expect(cached.fromCache, isTrue);
      },
    );

    test('mesmo GTIN permanece isolado por comércio e destino', () async {
      final first = await _createCommerce(access, 'one');
      final second = await _createCommerce(access, 'two');
      final now = DateTime.now().toIso8601String();
      for (final item in [
        ('p1', first.comercioId, 'loja'),
        ('p2', second.comercioId, 'loja'),
        ('p3', first.comercioId, 'salao'),
      ]) {
        await db.insert('estoque', {
          'id': item.$1,
          'comercio_id': item.$2,
          'estoque_destino': item.$3,
          'nome': 'Mesmo GTIN',
          'categoria': 'Teste',
          'tipo': 'produto',
          'codigo_barras': '7894900011517',
          'quantidade_atual': 1,
          'estoque_minimo': 0,
          'unidade': 'un',
          'custo_unitario': 1,
          'data_cadastro': now,
        });
      }

      final firstStore = await db.query(
        'estoque',
        where:
            "comercio_id = ? AND estoque_destino = 'loja' AND codigo_barras = ?",
        whereArgs: [first.comercioId, '7894900011517'],
      );
      expect(firstStore.map((row) => row['id']), ['p1']);
    });

    test(
      'catálogo global não possui custo, preço, estoque ou fornecedor',
      () async {
        final columns = await db.rawQuery(
          'PRAGMA table_info(catalogo_produtos)',
        );
        final names = columns.map((row) => row['name']).toSet();
        expect(names, isNot(contains('comercio_id')));
        expect(names, isNot(contains('custo')));
        expect(names, isNot(contains('preco_venda')));
        expect(names, isNot(contains('quantidade_atual')));
        expect(names, isNot(contains('fornecedor_id')));
      },
    );

    test('recursos dependentes de backend começam desativados', () async {
      final flags = await db.query(
        'feature_flags',
        where: 'chave IN (?, ?, ?, ?, ?)',
        whereArgs: [
          'customer_area',
          'nearby_salons',
          'whatsapp_official',
          'online_ai',
          'cloud_sync',
        ],
      );
      expect(flags, hasLength(5));
      expect(flags.every((row) => row['habilitada'] == 0), isTrue);
    });
  });
}

Future<UsuarioAcesso> _createCommerce(AcessoRepository access, String suffix) {
  return access.cadastrarComercio(
    CadastroComercioEntrada(
      nomeComercio: 'Studio $suffix',
      nomeExibicao: 'Studio $suffix',
      responsavel: 'Owner $suffix',
      telefone: '11999999999',
      email: 'owner.$suffix@studioflow.test',
      senha: 'Senha@123',
      permanecerConectado: false,
    ),
  );
}
