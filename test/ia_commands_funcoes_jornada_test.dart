import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/database/migrations/migration_v28.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/models/domain/atendimento.dart';
import 'package:studioflow/repositories/agenda_completa_repository.dart';
import 'package:studioflow/repositories/modalidades_repository.dart';
import 'package:studioflow/services/ia_command_service.dart';
import 'package:studioflow/services/session_controller.dart';
import 'package:studioflow/services/whatsapp_queue_service.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late IaCommandService commands;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 30,
        onConfigure: (d) => d.execute('PRAGMA foreign_keys=ON'),
        onCreate: DatabaseSchemaLatest.criar,
      ),
    );
    SessionController.instance.entrar(_owner());
    SessionController.instance.setUnidadeAtiva('unit-1');
    final now = DateTime.utc(2026, 8, 4).toIso8601String();
    await db.insert('comercios', {
      'id': 'commerce-1',
      'codigo_acesso': 'IA27',
      'nome': 'Studio',
      'nome_exibicao': 'Studio',
      'responsavel': 'Dona',
      'telefone': '1199',
      'email': 'dona@local',
      'ativo': 1,
      'criado_em': now,
      'atualizado_em': now,
    });
    // onCreate executa a migração antes do comércio existir; executá-la novamente sem perda semeia funções.
    await db.insert('unidades', {
      'id': 'unit-1',
      'comercio_id': 'commerce-1',
      'nome': 'Centro',
      'codigo': 'C',
      'principal': 1,
      'ativo': 1,
      'criado_em': now,
      'atualizado_em': now,
    });
    await db.insert('unidades', {
      'id': 'unit-2',
      'comercio_id': 'commerce-1',
      'nome': 'Norte',
      'codigo': 'N',
      'principal': 0,
      'ativo': 1,
      'criado_em': now,
      'atualizado_em': now,
    });
    await MigrationV28.executar(db);
    await db.insert('profissionais', {
      'id': 'prof-1',
      'comercio_id': 'commerce-1',
      'nome': 'Ana',
      'whatsapp': '',
      'email': '',
      'cargo': 'Manicure',
      'foto_perfil': '',
      'ativo': 1,
      'percentual_comissao': 50,
      'meta_mensal': 0,
      'faturamento_mes': 0,
      'data_cadastro': now,
    });
    await db.insert('servicos', {
      'id': 'service-1',
      'comercio_id': 'commerce-1',
      'nome': 'Manicure',
      'categoria': 'Unhas',
      'descricao': '',
      'preco': 40,
      'duracao_minutos': 60,
      'ativo': 1,
      'custo_estimado': 0,
      'data_cadastro': now,
    });
    await db.insert('profissional_servicos', {
      'profissional_id': 'prof-1',
      'servico_id': 'service-1',
    });
    await db.insert('clientes', {
      'id': 'client-ok',
      'comercio_id': 'commerce-1',
      'nome': 'Bia',
      'whatsapp': '11999999999',
      'consentimento_whatsapp': 1,
      'consentimento_marketing': 0,
      'total_gasto': 0,
      'total_atendimentos': 0,
      'observacoes': '',
      'data_cadastro': now,
      'ativo': 1,
    });
    await db.insert('clientes', {
      'id': 'client-no',
      'comercio_id': 'commerce-1',
      'nome': 'Cris',
      'whatsapp': '',
      'consentimento_whatsapp': 0,
      'consentimento_marketing': 0,
      'total_gasto': 0,
      'total_atendimentos': 0,
      'observacoes': '',
      'data_cadastro': now,
      'ativo': 1,
    });
    await _appointment(db, 'a1', 'client-ok', DateTime(2026, 8, 4, 10));
    await _appointment(db, 'a2', 'client-no', DateTime(2026, 8, 4, 11));
    commands = IaCommandService(
      databaseProvider: () async => db,
      whatsapp: WhatsappQueueService(databaseProvider: () async => db),
    );
  });
  tearDown(() async => db.close());

  test('diferencia consulta de comando operacional', () async {
    expect(await commands.prepare('Quantos agendamentos tenho hoje?'), isNull);
    final preview = await commands.prepare(
      'Envie lembrete para todos os agendamentos de hoje.',
      now: DateTime(2026, 8, 4, 9),
    );
    expect(preview?.kind, IaCommandKind.acao);
    expect(preview?.intent, 'enviar_lembretes_hoje');
    expect(preview?.fields['agendamentos'], 2);
    expect(preview?.fields['destinatarios_validos'], 1);
  });
  test(
    'confirma, enfileira, respeita consentimento e impede duplicidade',
    () async {
      final preview = (await commands.prepare(
        'Envie lembrete para os agendamentos de hoje.',
        now: DateTime(2026, 8, 4, 9),
      ))!;
      final first = await commands.execute(preview);
      expect(first.pending, 1);
      expect(first.ignored, 1);
      final second = await commands.execute(preview);
      expect(second.message, contains('já executada'));
      expect(await db.query('whatsapp_fila'), hasLength(1));
      expect(await db.query('ia_auditoria'), hasLength(1));
    },
  );
  test('extrai produto, marca, cor, quantidade, validade e código', () async {
    final p = (await commands.prepare(
      'Cadastre esmalte marca Anita cor preta, 2 unidades, vencimento dia 20/09/2026, código 789123.',
    ))!;
    expect(p.ready, isTrue);
    expect(p.fields['produto'], 'esmalte');
    expect(p.fields['marca'], 'anita');
    expect(p.fields['cor'], 'preta');
    expect(p.fields['quantidade'], 2);
    expect(p.fields['codigo_barras'], '789123');
    final result = await commands.execute(p);
    expect(result.recordId, isNotEmpty);
    expect(await db.query('estoque_lotes_ia'), hasLength(1));
    expect(await db.query('fila_sincronizacao'), isNotEmpty);
  });
  test('comando informal e data por extenso são compreendidos', () async {
    final preview = (await commands.prepare(
      'Cadastra esmalte marca Anita, 4 unidades, vencimento 20 de setembro de 2026, codigo 776655.',
      unitId: 'unit-1',
    ))!;
    expect(preview.ready, isTrue);
    expect(preview.fields['quantidade'], 4.0);
    expect(preview.fields['data_validade'], startsWith('2026-09-20'));
  });
  test('prévia cancelada não grava registro nem sincronização', () async {
    final beforeStock = await db.query('estoque');
    final beforeSync = await db.query('fila_sincronizacao');
    final preview = await commands.prepare(
      'Cadastre acetona, 2 unidades, codigo 554433.',
      unitId: 'unit-1',
    );
    expect(preview?.ready, isTrue);
    expect(await db.query('estoque'), hasLength(beforeStock.length));
    expect(await db.query('fila_sincronizacao'), hasLength(beforeSync.length));
  });

  test('ordem operacional sem permissão permanece bloqueada', () async {
    SessionController.instance.entrar(_restricted());
    final preview = (await commands.prepare('Inative o produto qualquer.'))!;
    await expectLater(commands.execute(preview), throwsStateError);
    SessionController.instance.entrar(_owner());
  });
  test('campos obrigatórios ausentes não executam', () async {
    final p = (await commands.prepare('Cadastre shampoo no estoque.'))!;
    expect(p.ready, isFalse);
    expect(() => commands.execute(p), throwsStateError);
  });
  test('cria serviço e vincula profissional real', () async {
    final p = (await commands.prepare(
      'Crie um serviço de design de sobrancelhas, duração de 40 minutos, valor de 50 reais, feito pela Ana.',
    ))!;
    final result = await commands.execute(p);
    expect(result.recordId, isNotEmpty);
    expect(
      await db.query(
        'profissional_servicos',
        where: 'servico_id=?',
        whereArgs: [result.recordId],
      ),
      hasLength(1),
    );
  });
  test(
    'colaborador aceita várias funções personalizadas sem duplicar',
    () async {
      final p = (await commands.prepare(
        'Cadastre a Maria como manicure e pedicure.',
      ))!;
      final result = await commands.execute(p);
      final links = await db.query(
        'profissional_funcoes',
        where: 'profissional_id=?',
        whereArgs: [result.recordId],
      );
      expect(links, hasLength(2));
      expect(
        await db.query(
          'profissionais',
          where: 'id=?',
          whereArgs: [result.recordId],
        ),
        hasLength(1),
      );
    },
  );
  test('jornada múltipla, intervalo, exceção e conflito real', () async {
    final repo = AgendaCompletaRepository(
      databaseProvider: () async => db,
      comercioId: 'commerce-1',
      usuarioId: 'user-1',
    );
    for (final day in [2, 3, 4, 5]) {
      await repo.salvarHorario(
        HorarioProfissional(
          id: '',
          profissionalId: 'prof-1',
          diaSemana: day,
          inicio: '08:00',
          fim: '18:00',
          intervaloInicio: '12:00',
          intervaloFim: '13:00',
          ativo: true,
        ),
      );
    }
    await repo.salvarHorario(
      const HorarioProfissional(
        id: '',
        profissionalId: 'prof-1',
        diaSemana: 6,
        inicio: '08:00',
        fim: '14:00',
        ativo: true,
      ),
    );
    final monday = await repo.horariosDisponiveis(
      profissionalId: 'prof-1',
      data: DateTime(2026, 8, 3),
      duracaoMinutos: 60,
    );
    expect(monday, isEmpty);
    final tuesday = await repo.horariosDisponiveis(
      profissionalId: 'prof-1',
      data: DateTime(2026, 8, 4),
      duracaoMinutos: 60,
    );
    expect(tuesday.any((e) => e.hour == 10), isFalse);
    expect(tuesday.any((e) => e.hour == 12), isFalse);
    final saturday = await repo.horariosDisponiveis(
      profissionalId: 'prof-1',
      data: DateTime(2026, 8, 8),
      duracaoMinutos: 60,
    );
    expect(saturday.last.hour, 13);
  });

  test(
    'modalidades são multimodais, reordenáveis e protegem histórico',
    () async {
      final repo = ModalidadesRepository(
        databaseProvider: () async => db,
        comercioId: 'commerce-1',
        usuarioId: 'user-1',
      );
      final initial = await repo.listar();
      expect(initial, hasLength(1));
      final customId = await repo.salvar(
        const ModalidadeRegistro(
          id: '',
          nome: 'Spa Capilar',
          descricao: 'Terapias e tratamentos',
          favorita: true,
        ),
      );
      await repo.vincularServico(customId, 'service-1');
      await repo.vincularProfissional(customId, 'prof-1');
      expect(
        await db.query(
          'modalidade_servicos',
          where: 'modalidade_id=?',
          whereArgs: [customId],
        ),
        hasLength(1),
      );
      await expectLater(
        repo.excluir(customId),
        throwsA(isA<ModalidadeExclusaoException>()),
      );
      await repo.alterarStatus(customId, false);
      expect(
        (await repo.listar()).firstWhere((e) => e.id == customId).ativa,
        isFalse,
      );
      await repo.alterarStatus(customId, true);
      await repo.reordenar([customId, initial.single.id]);
      expect((await repo.listar()).first.id, customId);
    },
  );

  test('IA edita lote, inativa produto e altera preço do serviço', () async {
    final create = (await commands.prepare(
      'Cadastre esmalte Anita preto, lote 123, 2 unidades, vencimento 20/09/2026, código 789123.',
      unitId: 'unit-1',
    ))!;
    final product = await commands.execute(create);
    final expiry = (await commands.prepare(
      'Altere o vencimento do lote 123 para 30/09/2026.',
    ))!;
    await commands.execute(expiry);
    final lots = await db.query(
      'estoque_lotes_ia',
      where: 'estoque_id=?',
      whereArgs: [product.recordId],
    );
    expect(lots.single['data_validade'], startsWith('2026-09-30'));

    final price = (await commands.prepare(
      'Corrija o preço do serviço Manicure para 60 reais.',
    ))!;
    await commands.execute(price);
    expect(
      (await db.query(
        'servicos',
        where: 'id=?',
        whereArgs: ['service-1'],
      )).single['preco'],
      60.0,
    );
    final inactive = (await commands.prepare(
      'Inative o produto esmalte Anita preto lote 123.',
    ))!;
    await commands.execute(inactive);
    expect(
      (await db.query(
        'estoque',
        where: 'id=?',
        whereArgs: [product.recordId],
      )).single['ativo'],
      0,
    );
  });

  test(
    'mesmo código com vencimento diferente cria lote e transfere unidade',
    () async {
      final first = (await commands.prepare(
        'Cadastre shampoo marca X, 3 unidades, vencimento 20/09/2026, código 998877.',
        unitId: 'unit-1',
      ))!;
      final product = await commands.execute(first);
      final second = (await commands.prepare(
        'Cadastre shampoo marca X, 2 unidades, vencimento 20/10/2026, código 998877.',
        unitId: 'unit-1',
      ))!;
      final reused = await commands.execute(second);
      expect(reused.recordId, product.recordId);
      expect(
        await db.query(
          'estoque_lotes_ia',
          where: 'estoque_id=?',
          whereArgs: [product.recordId],
        ),
        hasLength(2),
      );
      final transfer = (await commands.prepare(
        'Transfira 1 unidade do shampoo x para o estoque da unidade 2.',
        unitId: 'unit-1',
      ))!;
      expect(transfer.fields['unidade_destino'], '2');
      expect(await db.query('unidades', where: 'ativo=1'), hasLength(2));
      await commands.execute(transfer);
      final target = await db.query(
        'estoque_lotes_ia',
        where: 'estoque_id=? AND unidade_id=?',
        whereArgs: [product.recordId, 'unit-2'],
      );
      expect(target, hasLength(1));
      expect(target.single['quantidade'], 1.0);
    },
  );

  test(
    'IA reconhece modalidade ao criar serviço e vincular colaborador',
    () async {
      final repo = ModalidadesRepository(
        databaseProvider: () async => db,
        comercioId: 'commerce-1',
        usuarioId: 'user-1',
      );
      final modalityId = await repo.salvar(
        const ModalidadeRegistro(id: '', nome: 'Barbearia'),
      );
      final service = (await commands.prepare(
        'Crie um serviço de corte e barba na barbearia, duração de 45 minutos, valor de 70 reais.',
      ))!;
      final created = await commands.execute(service);
      expect(
        await db.query(
          'modalidade_servicos',
          where: 'modalidade_id=? AND servico_id=?',
          whereArgs: [modalityId, created.recordId],
        ),
        hasLength(1),
      );
      final link = (await commands.prepare(
        'Vincule Ana também à área de barbearia.',
      ))!;
      await commands.execute(link);
      expect(
        await db.query(
          'modalidade_profissionais',
          where: 'modalidade_id=? AND profissional_id=?',
          whereArgs: [modalityId, 'prof-1'],
        ),
        hasLength(1),
      );
    },
  );
}

Future<void> _appointment(
  Database db,
  String id,
  String client,
  DateTime start,
) => db.insert('agendamentos', {
  'id': id,
  'cliente_id': client,
  'servico_id': 'service-1',
  'profissional_id': 'prof-1',
  'inicio': start.toIso8601String(),
  'fim': start.add(const Duration(hours: 1)).toIso8601String(),
  'status': 'agendado',
  'observacoes': '',
  'confirmado': 0,
  'compareceu': 0,
  'valor_servico': 40,
  'excluido': 0,
  'encaixe': 0,
  'comercio_id': 'commerce-1',
  'unidade_id': 'unit-1',
  'data_criacao': DateTime.utc(2026, 8, 4).toIso8601String(),
  'created_at': DateTime.utc(2026, 8, 4).toIso8601String(),
  'updated_at': DateTime.utc(2026, 8, 4).toIso8601String(),
});
UsuarioAcesso _restricted() => UsuarioAcesso(
  id: 'user-restricted',
  comercioId: 'commerce-1',
  codigoComercio: 'IA27',
  nomeComercio: 'Studio',
  nomeExibicao: 'Studio',
  nome: 'Colaborador',
  telefone: '1199',
  emailLogin: 'colaborador@local',
  funcao: FuncaoUsuario.colaborador,
  ativo: true,
  permissoes: const {},
  acoes: const {},
);
UsuarioAcesso _owner() => UsuarioAcesso(
  id: 'user-1',
  comercioId: 'commerce-1',
  codigoComercio: 'IA27',
  nomeComercio: 'Studio',
  nomeExibicao: 'Studio',
  nome: 'Dona',
  telefone: '1199',
  emailLogin: 'dona@local',
  funcao: FuncaoUsuario.dono,
  ativo: true,
  permissoes: ModuloPermissao.values.toSet(),
  acoes: AcaoPermissao.values.toSet(),
);
