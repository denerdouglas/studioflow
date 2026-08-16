import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/repositories/loja_repository.dart';
import 'package:studioflow/services/session_controller.dart';

void main() {
  late Database db;

  UsuarioAcesso owner() => UsuarioAcesso(
    id: 'user_owner',
    comercioId: 'biz_a',
    codigoComercio: 'BIZ',
    nomeComercio: 'BIZ',
    nomeExibicao: 'BIZ',
    nome: 'Dono',
    telefone: '11999999999',
    emailLogin: 'a@a.com',
    funcao: FuncaoUsuario.dono,
    ativo: true,
    permissoes: ModuloPermissao.values.toSet(),
    acoes: AcaoPermissao.values.toSet(),
  );

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: DatabaseSchemaLatest.criar,
      ),
    );
    // Configurar sessÃ£o ativa usando o fluxo mockado
    SessionController.instance.entrar(owner());
  });

  test(
    'Resolução única de produto: nome, código de barras e código interno',
    () async {
      final lojaRepo = LojaRepository(databaseProvider: () async => db);

      // 1. Criar produto no banco
      await db.insert('estoque', {
        'id': 'prod1',
        'nome': 'Shampoo Especial',
        'categoria': 'Cabelo',
        'codigo_barras': '7891234567890',
        'codigo_interno': 'SHAMP-001',
        'tipo_produto': 'venda',
        'tipo': 'produto',
        'comercio_id': 'biz_a',
        'unidade': 'un',
        'ativo': 1,
        'data_cadastro': DateTime.now().toIso8601String(),
        'atualizado_em': DateTime.now().toIso8601String(),
        'estoque_destino': 'loja',
      });

      // 2. Pesquisar por nome vai falhar (nome nao eh mais ID forte)
      final porNome = await lojaRepo.buscarCodigo('Shampoo Especial');
      expect(porNome, isNull);

      // 3. Resolver pelo código de barras
      final porCodigoBarras = await lojaRepo.buscarCodigo('7891234567890');
      expect(porCodigoBarras, isNotNull);

      // Resolver pelo código interno
      final porCodigoInterno = await lojaRepo.buscarCodigo('SHAMP-001');
      expect(porCodigoInterno, isNotNull);

      // 4. Confirmar que a pesquisa textual (pesquisarProdutos / listarProdutos) CONTINUA achando o nome
      final resultadoPesquisa = await lojaRepo.listarProdutos(
        pesquisa: 'Shampoo',
      );
      expect(resultadoPesquisa.length, 1);
      expect(resultadoPesquisa.first.id, 'prod1');

      // 5. Confirmar que os outros retornam o MESMO ID
      expect(porCodigoBarras!.id, porCodigoInterno!.id);
      expect(porCodigoBarras.id, 'prod1');
    },
  );
}
