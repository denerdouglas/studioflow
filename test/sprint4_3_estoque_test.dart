import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/repositories/acesso_repository.dart';
import 'package:studioflow/models/domain/agendamento_grupo_registro.dart';
import 'package:studioflow/repositories/agenda_repository.dart';
import 'package:studioflow/services/session_controller.dart';
import 'package:studioflow/database/database_service.dart';
import 'package:studioflow/core/constants/database_constants.dart';
import 'dart:convert';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final path = '${await getDatabasesPath()}/${DatabaseConstants.nomeArquivo}';
    await databaseFactoryFfi.deleteDatabase(path);

    final db = await DatabaseService.instance.database;

    // Configurar sessÃ£o ativa usando o fluxo real para criar o business_id
    final acesso = AcessoRepository();
    final usuario = await acesso.cadastrarComercio(
      const CadastroComercioEntrada(
        nomeComercio: 'Comercio Teste 4.3',
        nomeExibicao: 'Teste 4.3',
        responsavel: 'Dono',
        telefone: '11999999999',
        email: 'teste@43.com',
        senha: 'Senha@123',
        permanecerConectado: false,
      ),
    );
    final bizId = usuario.comercioId;
    SessionController.instance.entrar(usuario);

    // Inserir dados mÃ­nimos (profissionais, clientes, serviÃ§os)
    await db.insert('clientes', {
      'id': 'cli1',
      'nome': 'Cliente',
      'comercio_id': bizId,
      'telefone': '11999999999',
      'whatsapp': '11999999999',
      'data_cadastro': DateTime.now().toIso8601String(),
    });
    await db.insert('profissionais', {
      'id': 'prof1',
      'nome': 'Profissional',
      'comercio_id': bizId,
      'ativo': 1,
      'whatsapp': '11999999999',
      'cargo': 'Cabeleireiro',
      'data_cadastro': DateTime.now().toIso8601String(),
    });
    await db.insert('servicos', {
      'id': 'srv1',
      'nome': 'Servico',
      'comercio_id': bizId,
      'ativo': 1,
      'preco': 100,
      'duracao_minutos': 30,
      'categoria': 'Geral',
      'data_cadastro': DateTime.now().toIso8601String(),
    });
    await db.insert('estoque', {
      'id': 'prod1',
      'nome': 'Produto X',
      'comercio_id': bizId,
      'ativo': 1,
      'categoria': 'Consumo',
      'tipo': 'produto',
      'unidade': 'ml',
      'data_cadastro': DateTime.now().toIso8601String(),
    });

    // Inserir material do serviÃ§o
    await db.insert('servico_materiais', {
      'id': 'sm1',
      'servico_id': 'srv1',
      'estoque_id': 'prod1',
      'quantidade': 30,
      'unidade_medida': 'ml',
      'comercio_id': bizId,
    });

    // Inserir estoque inicial uso_interno
    await db.insert('estoque_saldos', {
      'id': 'saldo1',
      'business_id': bizId,
      'estoque_id': 'prod1',
      'finalidade': 'uso_interno',
      'quantidade_atual': 100,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  });

  tearDown(() async {
    await DatabaseService.instance.fecharBanco();
  });

  test(
    'Agendamento nÃ£o deduz estoque, apenas salva consumo_previsto_json',
    () async {
      final agendaRepo = AgendaRepository();
      final inicio = DateTime.now();
      final fim = inicio.add(const Duration(minutes: 30));

      final bizId = SessionController.instance.usuario!.comercioId;

      final grupo = AgendamentoGrupoRegistro(
        id: 'grupo1',
        businessId: bizId,
        clienteId: 'cli1',
        status: 'agendado',
        createdAt: inicio,
        updatedAt: inicio,
      );

      final agendamento = AgendamentoRegistro(
        id: 'ag1',
        clienteId: 'cli1',
        clienteNome: 'Cliente',
        profissionalId: 'prof1',
        profissionalNome: 'Profissional',
        servicoId: 'srv1',
        servicoNome: 'Servico',
        inicio: inicio,
        fim: fim,
        status: 'agendado',
        valorServico: 100,
        desconto: 0,
        valorRecebido: 0,
        confirmado: false,
        compareceu: false,
        dataCriacao: inicio,
      );

      final db = await DatabaseService.instance.database;
      final consumoPrevisto = [
        {'produtoId': 'prod1', 'quantidade': 30},
      ];
      await db.insert('servicos', {
        'id': 'srv1',
        'comercio_id': bizId,
        'nome': 'Servico',
        'preco': 100,
        'duracao_minutos': 30,
        'categoria': 'Geral',
        'data_cadastro': inicio.toIso8601String(),
        'insumos_json': jsonEncode(consumoPrevisto),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await agendaRepo.inserirGrupo(grupo, [agendamento]);

      final agCriado = await agendaRepo.buscarPorId('ag1');
      expect(agCriado, isNotNull);
      expect(agCriado!.consumoPrevistoJson, isNotNull);

      final previsto = jsonDecode(agCriado.consumoPrevistoJson!) as List;
      expect(previsto.length, 1);
      expect(previsto[0]['produto_id'], 'prod1');
      expect(previsto[0]['quantidade'], 30);
      expect(agCriado.estoqueConsumido, false);

      // Saldo nÃ£o alterado
      final saldo = await db.query(
        'estoque_saldos',
        where: 'estoque_id = ? AND business_id = ? AND finalidade = ?',
        whereArgs: ['prod1', bizId, 'uso_interno'],
      );
      expect(saldo.first['quantidade_atual'], 100.0);
    },
  );

  test(
    'Concluir atendimento com estoque deduz uso_interno corretamente e garante idempotÃªncia',
    () async {
      final agendaRepo = AgendaRepository();
      final inicio = DateTime.now();
      final bizId = SessionController.instance.usuario!.comercioId;
      final db = await DatabaseService.instance.database;

      // Configura agendamento sem estoque deduzido
      await db.insert('agendamentos', {
        'id': 'ag2',
        'cliente_id': 'cli1',
        'profissional_id': 'prof1',
        'servico_id': 'srv1',
        'inicio': inicio.toIso8601String(),
        'fim': inicio.add(const Duration(minutes: 30)).toIso8601String(),
        'status': 'agendado',
        'valor_servico': 100,
        'desconto': 0,
        'valor_recebido': 0,
        'observacoes': '',
        'consumo_previsto_json': null,
        'consumo_realizado_json': null,
        'estoque_consumido': 0,
        'confirmado': 0, // Restored
        'compareceu': 0, // Restored
        'excluido': 0, // Restored
        'data_criacao': inicio.toIso8601String(), // Restored
        'comercio_id': bizId,
        'business_id': bizId,
        'created_at': inicio.toIso8601String(),
        'updated_at': inicio.toIso8601String(),
      });

      final consumoEfetivo = [
        {'produto_id': 'prod1', 'quantidade': 30.0, 'unidade': 'ml'},
      ];

      // Conclui primeira vez
      await agendaRepo.concluirAtendimentoComEstoque(
        agendamentoId: 'ag2',
        valorRecebido: 100,
        consumoEfetivo: consumoEfetivo,
        profissionalId: 'prof1',
      );

      // Saldo alterado
      var saldo = await db.query(
        'estoque_saldos',
        where: 'estoque_id = ? AND business_id = ? AND finalidade = ?',
        whereArgs: ['prod1', bizId, 'uso_interno'],
      );
      expect(saldo.first['quantidade_atual'], 70.0); // 100 - 30

      // MovimentaÃ§Ã£o criada
      var movs = await db.query(
        'movimentacoes_estoque',
        where: 'agendamento_id = ?',
        whereArgs: ['ag2'],
      );
      expect(movs.length, 1);
      expect(movs.first['quantidade'], 30.0);
      expect(movs.first['idempotency_key'], '${bizId}_ag2_prod1_uso_interno');

      // Conclui SEGUNDA vez (cenÃ¡rio idempotente)
      await agendaRepo.concluirAtendimentoComEstoque(
        agendamentoId: 'ag2',
        valorRecebido: 100,
        consumoEfetivo: consumoEfetivo,
        profissionalId: 'prof1',
      );

      // Saldo DEVE CONTINUAR 70
      saldo = await db.query(
        'estoque_saldos',
        where: 'estoque_id = ? AND business_id = ? AND finalidade = ?',
        whereArgs: ['prod1', bizId, 'uso_interno'],
      );
      expect(saldo.first['quantidade_atual'], 70.0);

      // MovimentaÃ§Ã£o nÃ£o duplicou
      movs = await db.query(
        'movimentacoes_estoque',
        where: 'agendamento_id = ?',
        whereArgs: ['ag2'],
      );
      expect(movs.length, 1);
    },
  );
}
