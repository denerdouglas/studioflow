import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../models/domain/acesso.dart';
import '../models/domain/pacote_servico.dart';
import '../services/session_controller.dart';
import 'agenda_completa_repository.dart';
import 'agenda_repository.dart' show ConflitoAgendaException;

class PacotesRepository {
  Future<Database> get databaseForUI async => _databaseProvider();
  String get comercioIdForUI => _comercioId;

  Future<PreviaAgendaPacote> gerarPreviaSimulada({
    required String pacoteId,
    required SolicitacaoAgendaPacote solicitacao,
  }) async {
    _exigir(AcaoPermissao.venderPacotes);
    final db = await _databaseProvider();

    final itens = await db.rawQuery(
      '''SELECT pi.*, s.nome AS servico_nome 
         FROM pacote_itens pi 
         JOIN servicos s ON s.id=pi.servico_id 
         WHERE pi.pacote_id=? AND pi.ativo=1
         ORDER BY COALESCE(pi.ordem, 9999), pi.id''',
      [pacoteId],
    );
    if (itens.isEmpty) {
      return const PreviaAgendaPacote(sessoes: [], naoEncaixadas: []);
    }

    final profissional = await db.query(
      'profissionais',
      columns: ['id', 'nome'],
      where: 'id=? AND comercio_id=? AND ativo=1',
      whereArgs: [solicitacao.profissionalId, _comercioId],
      limit: 1,
    );
    if (profissional.isEmpty) throw StateError('Profissional indisponível.');

    final planejadas = <SessaoPlanejadaPacote>[];
    final falhas = <String>[];
    var alvo = solicitacao.primeiraData;
    DateTime? anterior;
    final agenda = AgendaCompletaRepository(
      databaseProvider: _databaseProvider,
      comercioId: _comercioId,
      usuarioId: _usuarioId,
    );

    var fakeId = 0;
    for (final item in itens) {
      final qtd = item['quantidade_sessoes'] as int;
      for (var i = 0; i < qtd; i++) {
        fakeId++;
        final autorizados = await db.query(
          'pacote_item_profissionais',
          columns: ['profissional_id'],
          where: 'comercio_id=? AND pacote_item_id=?',
          whereArgs: [_comercioId, item['id']],
        );
        if (autorizados.isNotEmpty &&
            !autorizados.any(
              (r) => r['profissional_id'] == solicitacao.profissionalId,
            )) {
          falhas.add('${item['servico_nome']}: profissional não autorizado.');
          continue;
        }
        if (anterior != null) {
          final minimo = 0; // Simulando sem mínimo
          final minimoData = anterior.add(Duration(days: minimo));
          if (alvo.isBefore(minimoData)) alvo = minimoData;
        }

        final desejado = DateTime(
          alvo.year,
          alvo.month,
          alvo.day,
          solicitacao.horaPreferida,
          solicitacao.minutoPreferido,
        );

        DateTime? escolhido;
        final limiteBusca = alvo.add(
          Duration(days: solicitacao.limiteBuscaDias),
        );
        var diaBusca = alvo;
        final duracao = item['duracao_prevista'] as int;
        while (escolhido == null && diaBusca.isBefore(limiteBusca)) {
          if (!solicitacao.diasSemana.contains(diaBusca.weekday)) {
            diaBusca = diaBusca.add(const Duration(days: 1));
            continue;
          }
          final livres = await agenda.horariosDisponiveis(
            profissionalId: solicitacao.profissionalId,
            data: diaBusca,
            duracaoMinutos: duracao,
          );
          if (livres.isNotEmpty) {
            final aptos = livres
                .where(
                  (h) =>
                      (h.hour > desejado.hour ||
                          (h.hour == desejado.hour &&
                              h.minute >= desejado.minute)) ||
                      (desejado.difference(h).inMinutes <=
                          120), // Consider anything close
                )
                .toList();
            if (aptos.isNotEmpty) {
              aptos.sort(
                (a, b) => a
                    .difference(desejado)
                    .abs()
                    .compareTo(b.difference(desejado).abs()),
              );
              escolhido = aptos.first;
            } else {
              // Just take any
              escolhido = livres.first;
            }
          } else {
            diaBusca = diaBusca.add(const Duration(days: 1));
          }
        }

        if (escolhido == null) {
          falhas.add('${item['servico_nome']}: nenhum horário compatível.');
          continue;
        }

        planejadas.add(
          SessaoPlanejadaPacote(
            sessaoId: 'sim_$fakeId',
            servicoId: item['servico_id'] as String,
            servicoNome: item['servico_nome'] as String,
            profissionalId: solicitacao.profissionalId,
            profissionalNome: profissional.first['nome'] as String,
            inicio: escolhido,
            duracaoMinutos: item['duracao_prevista'] as int,
            horarioAlternativo:
                escolhido.day != desejado.day ||
                escolhido.hour != desejado.hour ||
                escolhido.minute != desejado.minute,
            aviso: escolhido == desejado
                ? null
                : 'Horário alternativo mais próximo.',
          ),
        );
        anterior = escolhido;
        if (solicitacao.frequencia == FrequenciaAgendamentoPacote.semanal) {
          alvo = alvo.add(Duration(days: 7 * solicitacao.intervalo));
        } else if (solicitacao.frequencia ==
            FrequenciaAgendamentoPacote.mensal) {
          alvo = DateTime(
            alvo.year,
            alvo.month + solicitacao.intervalo,
            alvo.day,
          );
        } else {
          alvo = alvo.add(Duration(days: solicitacao.intervalo));
        }
      }
    }
    return PreviaAgendaPacote(sessoes: planejadas, naoEncaixadas: falhas);
  }

  Future<String> venderEAgendar({
    required VendaPacoteEntrada entrada,
    List<SessaoPlanejadaPacote>? agendamentos,
    required String pacoteNome,
  }) async {
    _exigir(AcaoPermissao.venderPacotes);
    final db = await _databaseProvider();
    final vendaId = _id('pve');

    await db.transaction((txn) async {
      // 1. Vender pacote
      final pacoteRows = await txn.query(
        'pacotes',
        where: 'id=?',
        whereArgs: [entrada.pacoteId],
        limit: 1,
      );
      if (pacoteRows.isEmpty) throw ArgumentError('Pacote não encontrado.');
      final pacote = pacoteRows.first;
      final preco = (pacote['preco'] as num).toDouble();
      final contratado = preco - entrada.desconto;
      final pago = entrada.valorPagoInicial;
      final compra = entrada.dataCompra;
      final validade = compra.add(
        Duration(days: pacote['validade_dias'] as int),
      );
      final agora = _agora();

      final totalSessoes =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT SUM(quantidade_sessoes) FROM pacote_itens WHERE pacote_id=?',
              [entrada.pacoteId],
            ),
          ) ??
          0;

      await txn.insert('pacotes_vendidos', {
        'id': vendaId,
        'business_id': _comercioId,
        'pacote_id': entrada.pacoteId,
        'cliente_id': entrada.clienteId,
        'data_venda': compra.toIso8601String(),
        'valor_original': preco,
        'desconto': entrada.desconto,
        'valor_final': contratado,
        'forma_pagamento': entrada.formaPagamento,
        'status': 'ativo',
        'validade_inicio': compra.toIso8601String(),
        'validade_fim': validade.toIso8601String(),
        'quantidade_sessoes': totalSessoes,
        'sessoes_utilizadas': 0,
        'sessoes_restantes': totalSessoes,
        'observacoes': entrada.comandaReferencia ?? '',
        'created_by': _usuarioId,
        'created_at': agora,
        'updated_at': agora,
      });

      final itens = await txn.query(
        'pacote_itens',
        where: 'pacote_id=? AND ativo=1',
        whereArgs: [entrada.pacoteId],
        orderBy: 'COALESCE(ordem, 9999), id',
      );

      final sessoesCriadasIds = <String>[];
      for (final item in itens) {
        for (var i = 0; i < (item['quantidade_sessoes'] as int); i++) {
          final sessaoId = _id('pvs');
          sessoesCriadasIds.add(sessaoId);
          await txn.insert('sessoes_pacotes', {
            'id': sessaoId,
            'business_id': _comercioId,
            'pacote_vendido_id': vendaId,
            'servico_id_previsto': item['servico_id'],
            'ordem': item['ordem'] == null ? null : (item['ordem'] as int) + i,
            'status': 'disponivel',
            'created_at': agora,
            'updated_at': agora,
          });
        }
      }

      if (pago > 0) {
        await _registrarPagamentoTxn(
          txn,
          vendaId: vendaId,
          valor: pago,
          formaPagamento: entrada.formaPagamento,
        );
      }

      await _auditar(
        txn,
        acao: 'pacote_vendido',
        vendaId: vendaId,
        pacoteId: entrada.pacoteId,
        dados: {'valor': contratado, 'cliente_id': entrada.clienteId},
      );

      // 2. Confirmar prévia agendada
      if (agendamentos != null && agendamentos.isNotEmpty) {
        if (agendamentos.length > sessoesCriadasIds.length) {
          throw StateError('Agendamentos excedem as sessões disponíveis.');
        }
        for (int i = 0; i < agendamentos.length; i++) {
          final item = agendamentos[i];
          final realSessaoId = sessoesCriadasIds[i];

          final conflitos = await txn.query(
            'agendamentos',
            columns: ['id'],
            where:
                "comercio_id=? AND profissional_id=? AND status!='cancelado' AND inicio<? AND fim>?",
            whereArgs: [
              _comercioId,
              item.profissionalId,
              item.fim.toIso8601String(),
              item.inicio.toIso8601String(),
            ],
            limit: 1,
          );
          final bloqueios = await txn.query(
            'bloqueios_agenda',
            columns: ['id'],
            where:
                'comercio_id=? AND (profissional_id IS NULL OR profissional_id=?) AND inicio<? AND fim>?',
            whereArgs: [
              _comercioId,
              item.profissionalId,
              item.fim.toIso8601String(),
              item.inicio.toIso8601String(),
            ],
            limit: 1,
          );
          if (conflitos.isNotEmpty || bloqueios.isNotEmpty) {
            throw StateError(
              'Um horário da prévia (${item.inicio}) não está mais disponível para ${item.profissionalNome}.',
            );
          }
          final agendamentoId = _id('ag');
          await txn.insert('agendamentos', {
            'id': agendamentoId,
            'comercio_id': _comercioId,
            'cliente_id': entrada.clienteId,
            'profissional_id': item.profissionalId,
            'servico_id': item.servicoId,
            'inicio': item.inicio.toIso8601String(),
            'fim': item.fim.toIso8601String(),
            'status': 'agendado',
            'forma_pagamento': 'Pacote',
            'valor_servico': 0,
            'desconto': 0,
            'valor_recebido': 0,
            'confirmado': 0,
            'compareceu': 0,
            'observacoes': 'Sessão de pacote; receita registrada na venda.',
            'data_criacao': agora,
            'created_by': _usuarioId,
            'created_at': agora,
            'updated_at': agora,
          });
          await txn.update(
            'sessoes_pacotes',
            {
              'status': 'agendada',
              'agendamento_id': agendamentoId,
              'profissional_id': item.profissionalId,
              'data_agendada': item.inicio.toIso8601String().split('T')[0],
              'horario_inicio':
                  '${item.inicio.hour.toString().padLeft(2, '0')}:${item.inicio.minute.toString().padLeft(2, '0')}',
              'horario_fim':
                  '${item.fim.hour.toString().padLeft(2, '0')}:${item.fim.minute.toString().padLeft(2, '0')}',
              'updated_at': agora,
            },
            where: 'id=?',
            whereArgs: [realSessaoId],
          );
        }
      }
    });

    // 3. Fila WhatsApp
    try {
      final db = await _databaseProvider();
      final cliente = await db.query(
        'clientes',
        columns: ['telefone'],
        where: 'id=? AND comercio_id=?',
        whereArgs: [entrada.clienteId, _comercioId],
        limit: 1,
      );
      final telefone = cliente.isNotEmpty
          ? cliente.first['telefone'] as String?
          : null;

      final sessoesJson = (agendamentos ?? [])
          .map(
            (s) => {
              "numero": agendamentos!.indexOf(s) + 1,
              "servico": s.servicoNome,
              "data": s.inicio.toIso8601String().split('T')[0],
              "hora":
                  '${s.inicio.hour.toString().padLeft(2, '0')}:${s.inicio.minute.toString().padLeft(2, '0')}',
              "profissional": s.profissionalNome,
            },
          )
          .toList();

      final payloadJson = {
        "tipo": "novo_pacote",
        "pacote_id": entrada.pacoteId,
        "pacote_vendido_id": vendaId,
        "cliente_id": entrada.clienteId,
        "pacote_nome": pacoteNome,
        "valor": entrada.valorPagoInicial,
        "status_financeiro": "ativo",
        "sessoes": sessoesJson,
      };

      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('whatsapp_fila', {
        'id': _id('waf'),
        'business_id': _comercioId,
        'cliente_id': entrada.clienteId,
        'destinatario': telefone ?? '',
        'agendamento_id': null,
        'status': 'na_fila',
        'provider': 'system',
        'idempotency_key': 'venda_pacote_$vendaId',
        'template_id': null,
        'payload': jsonEncode(payloadJson),
        'created_at': now,
        'updated_at': now,
      });
    } catch (e) {
      // Ignore Whatsapp enqueue failure as per user requirements
      print('Falha ao enfileirar WhatsApp: $e');
    }

    return vendaId;
  }

  final Future<Database> Function() _databaseProvider;
  final String? _comercioInformado;
  final String? _usuarioInformado;

  PacotesRepository({
    Future<Database> Function()? databaseProvider,
    String? comercioId,
    String? usuarioId,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseService.instance.database),
       _comercioInformado = comercioId,
       _usuarioInformado = usuarioId;

  String get _comercioId =>
      _comercioInformado ?? SessionController.instance.usuario!.comercioId;
  String get _usuarioId =>
      _usuarioInformado ?? SessionController.instance.usuario!.id;

  void _exigir(AcaoPermissao acao) {
    final usuario = SessionController.instance.usuario;
    if (usuario == null && _comercioInformado != null) return;
    if (usuario == null || !usuario.podeAcao(acao)) {
      throw StateError('Você não possui permissão para ${acao.nome}.');
    }
  }

  String _id(String prefixo) => '${prefixo}_${IdGenerator.temporal()}';
  String _agora() => DateTime.now().toUtc().toIso8601String();

  Future<List<Map<String, Object?>>> listarServicosAtivos() async {
    final db = await _databaseProvider();
    return db.query(
      'servicos',
      where: 'comercio_id=? AND ativo=1',
      whereArgs: [_comercioId],
      orderBy: 'nome COLLATE NOCASE',
    );
  }

  Future<List<Map<String, Object?>>> listarClientesAtivos() async {
    final db = await _databaseProvider();
    return db.query(
      'clientes',
      columns: ['id', 'nome'],
      where: 'comercio_id=? AND ativo=1',
      whereArgs: [_comercioId],
      orderBy: 'nome COLLATE NOCASE',
    );
  }

  Future<List<Map<String, Object?>>> listarProfissionaisAtivos() async {
    final db = await _databaseProvider();
    return db.query(
      'profissionais',
      columns: ['id', 'nome'],
      where: 'comercio_id=? AND ativo=1',
      whereArgs: [_comercioId],
      orderBy: 'nome COLLATE NOCASE',
    );
  }

  Future<List<Map<String, Object?>>> listarModelos({
    bool incluirInativos = true,
  }) async {
    _exigir(AcaoPermissao.visualizarPacotes);
    final db = await _databaseProvider();
    return db.rawQuery(
      '''SELECT p.*,
        (SELECT GROUP_CONCAT(s.nome || ' ×' || i.quantidade_sessoes, ', ')
         FROM pacote_itens i
         JOIN servicos s ON s.id=i.servico_id
         WHERE i.pacote_id=p.id) AS itens_resumo
       FROM pacotes p
       WHERE p.business_id=? ${incluirInativos ? '' : "AND p.status=1"}
       ORDER BY p.status DESC, p.nome COLLATE NOCASE''',
      [_comercioId],
    );
  }

  Future<List<Map<String, Object?>>> listarItens(String pacoteId) async {
    final db = await _databaseProvider();
    return db.rawQuery(
      '''SELECT i.*, s.nome AS servico_nome
         FROM pacote_itens i
         JOIN servicos s ON s.id=i.servico_id
         WHERE i.pacote_id=?
         ORDER BY COALESCE(i.ordem, 9999), s.nome''',
      [pacoteId],
    );
  }

  Future<String> salvarModelo(PacoteEntrada entrada) async {
    _exigir(
      entrada.id == null
          ? AcaoPermissao.criarPacotes
          : AcaoPermissao.editarPacotes,
    );
    if (entrada.nome.trim().isEmpty ||
        entrada.categoria.trim().isEmpty ||
        entrada.itens.isEmpty ||
        entrada.precoPacote < 0 ||
        entrada.validadeDias <= 0) {
      throw ArgumentError(
        'Preencha nome, categoria, serviços, preço e validade.',
      );
    }
    if (entrada.itens.any(
      (i) =>
          i.quantidade <= 0 ||
          i.intervaloMinimoDias < 0 ||
          (i.intervaloMaximoDias != null &&
              i.intervaloMaximoDias! < i.intervaloMinimoDias),
    )) {
      throw ArgumentError('Quantidade ou intervalo de serviço inválido.');
    }
    if (entrada.tipoSequencia == TipoSequenciaPacote.obrigatoria &&
        entrada.itens.any((i) => i.ordemInicial == null)) {
      throw ArgumentError('Informe a ordem de todos os serviços do pacote.');
    }
    final db = await _databaseProvider();
    final id = entrada.id ?? _id('pct');
    await db.transaction((txn) async {
      final servicos = <String, Map<String, Object?>>{};
      for (final item in entrada.itens) {
        final rows = await txn.query(
          'servicos',
          where: 'id=? AND comercio_id=?',
          whereArgs: [item.servicoId, _comercioId],
          limit: 1,
        );
        if (rows.isEmpty) {
          throw StateError('Serviço não encontrado neste comércio.');
        }
        servicos[item.servicoId] = rows.first;
      }
      final totalSessoes = entrada.itens.fold<int>(
        0,
        (total, item) => total + item.quantidade,
      );
      final soma = entrada.itens.fold<double>(0, (total, item) {
        return total +
            (servicos[item.servicoId]!['preco'] as num).toDouble() *
                item.quantidade;
      });
      final agora = _agora();
      final mapa = <String, Object?>{
        'id': id,
        'business_id': _comercioId,
        'nome': entrada.nome.trim(),
        'preco': entrada.precoPacote,
        'validade_dias': entrada.validadeDias,
        'regras_uso': entrada.regrasCancelamento.trim(),
        'status': entrada.ativo ? 'ativo' : 'inativo',
        'created_by': _usuarioId,
        'created_at': agora,
        'updated_at': agora,
      };
      if (entrada.id == null) {
        await txn.insert('pacotes', mapa);
      } else {
        mapa.remove('id');
        mapa.remove('business_id');
        mapa.remove('created_at');
        await txn.update(
          'pacotes',
          mapa,
          where: 'id=? AND business_id=?',
          whereArgs: [id, _comercioId],
        );
        await txn.delete(
          'pacote_itens',
          where: 'pacote_id=? AND business_id=?',
          whereArgs: [id, _comercioId],
        );
      }
      for (final item in entrada.itens) {
        final servico = servicos[item.servicoId]!;
        final itemId = _id('pitem');
        await txn.insert('pacote_itens', {
          'id': itemId,
          'pacote_id': id,
          'servico_id': item.servicoId,
          'quantidade_sessoes': item.quantidade,
          'ordem': item.ordemInicial,
          'duracao_prevista': item.duracaoMinutos ?? servico['duracao_minutos'],
          'valor_referencia': servico['preco'],
          'profissional_obrigatorio_id':
              item.profissionaisAutorizados.isNotEmpty
              ? item.profissionaisAutorizados.first
              : null,
          'ativo': 1,
          'created_at': agora,
          'updated_at': agora,
          'created_by': _usuarioId,
        });
      }
      await _auditar(
        txn,
        acao: entrada.id == null ? 'modelo_criado' : 'modelo_editado',
        pacoteId: id,
        dados: {'nome': entrada.nome, 'total_sessoes': totalSessoes},
      );
      await _enfileirar(
        txn,
        'pacote',
        id,
        entrada.id == null ? 'criar' : 'editar',
      );
    });
    return id;
  }

  Future<void> alterarModeloAtivo(String id, bool ativo) async {
    _exigir(AcaoPermissao.editarPacotes);
    final db = await _databaseProvider();
    await db.update(
      'pacotes',
      {'status': ativo ? 'ativo' : 'inativo', 'updated_at': _agora()},
      where: 'id=? AND business_id=?',
      whereArgs: [id, _comercioId],
    );
  }

  Future<String> vender(VendaPacoteEntrada entrada) async {
    _exigir(AcaoPermissao.venderPacotes);
    if (entrada.desconto > 0) _exigir(AcaoPermissao.aplicarDescontoPacote);
    final db = await _databaseProvider();
    final vendaId = _id('pv');
    await db.transaction((txn) async {
      final pacotes = await txn.query(
        'pacotes',
        where: 'id=? AND business_id=? AND status=?',
        whereArgs: [entrada.pacoteId, _comercioId, 'ativo'],
        limit: 1,
      );
      if (pacotes.isEmpty) throw StateError('Pacote inativo ou inexistente.');
      final pacote = pacotes.first;
      for (final alvo in [
        ['clientes', entrada.clienteId],
        ['profissionais', entrada.vendedorProfissionalId],
      ]) {
        final rows = await txn.query(
          alvo[0],
          columns: ['id'],
          where: 'id=? AND comercio_id=?',
          whereArgs: [alvo[1], _comercioId],
          limit: 1,
        );
        if (rows.isEmpty) throw StateError('Cliente ou vendedor inválido.');
      }
      final preco = (pacote['preco'] as num).toDouble();
      if (entrada.desconto < 0 || entrada.desconto > preco) {
        throw ArgumentError('Desconto inválido.');
      }
      final contratado = preco - entrada.desconto;
      final pago = entrada.valorPagoInicial;
      if (pago < 0 || pago > contratado) {
        throw ArgumentError('Pagamento inválido.');
      }
      if (entrada.parcelas > 1) {
        throw StateError(
          'Este pacote não permite parcelamento no novo schema.',
        );
      }
      if (entrada.parcelas < 1) {
        throw ArgumentError('Quantidade de parcelas inválida.');
      }
      final compra = entrada.dataCompra;
      final validade = compra.add(
        Duration(days: pacote['validade_dias'] as int),
      );
      final agora = _agora();
      final totalSessoes =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT SUM(quantidade_sessoes) FROM pacote_itens WHERE pacote_id=?',
              [entrada.pacoteId],
            ),
          ) ??
          0;

      await txn.insert('pacotes_vendidos', {
        'id': vendaId,
        'business_id': _comercioId,
        'pacote_id': entrada.pacoteId,
        'cliente_id': entrada.clienteId,
        'data_venda': compra.toIso8601String(),
        'valor_original': preco,
        'desconto': entrada.desconto,
        'valor_final': contratado,
        'forma_pagamento': entrada.formaPagamento,
        'status': 'ativo',
        'validade_inicio': compra.toIso8601String(),
        'validade_fim': validade.toIso8601String(),
        'quantidade_sessoes': totalSessoes,
        'sessoes_utilizadas': 0,
        'sessoes_restantes': totalSessoes,
        'observacoes': entrada.comandaReferencia ?? '',
        'created_by': _usuarioId,
        'created_at': agora,
        'updated_at': agora,
      });
      final itens = await txn.query(
        'pacote_itens',
        where: 'pacote_id=? AND ativo=1',
        whereArgs: [entrada.pacoteId],
        orderBy: 'COALESCE(ordem, 9999), id',
      );
      for (final item in itens) {
        for (var i = 0; i < (item['quantidade_sessoes'] as int); i++) {
          await txn.insert('sessoes_pacotes', {
            'id': _id('pvs'),
            'business_id': _comercioId,
            'pacote_vendido_id': vendaId,
            'servico_id_previsto': item['servico_id'],
            'ordem': item['ordem'] == null ? null : (item['ordem'] as int) + i,
            'status': 'disponivel',
            'created_at': agora,
            'updated_at': agora,
          });
        }
      }
      final saldo = contratado - pago;
      final valorParcela = entrada.parcelas == 0
          ? saldo
          : saldo / entrada.parcelas;
      // Parcelas handled by external financial module now
      if (pago > 0) {
        await _registrarPagamentoTxn(
          txn,
          vendaId: vendaId,
          valor: pago,
          formaPagamento: entrada.formaPagamento,
        );
      }
      await _auditar(
        txn,
        acao: 'pacote_vendido',
        vendaId: vendaId,
        pacoteId: entrada.pacoteId,
        dados: {'valor': contratado, 'cliente_id': entrada.clienteId},
      );
      await _enfileirar(txn, 'pacote_venda', vendaId, 'criar');
    });
    return vendaId;
  }

  Future<void> registrarPagamento({
    required String vendaId,
    required double valor,
    required String formaPagamento,
  }) async {
    _exigir(AcaoPermissao.venderPacotes);
    if (valor <= 0) throw ArgumentError('O pagamento deve ser positivo.');
    final db = await _databaseProvider();
    await db.transaction(
      (txn) => _registrarPagamentoTxn(
        txn,
        vendaId: vendaId,
        valor: valor,
        formaPagamento: formaPagamento,
      ),
    );
  }

  Future<void> _registrarPagamentoTxn(
    DatabaseExecutor txn, {
    required String vendaId,
    required double valor,
    required String formaPagamento,
  }) async {
    final vendas = await txn.query(
      'pacotes_vendidos',
      where: 'id=? AND business_id=?',
      whereArgs: [vendaId, _comercioId],
      limit: 1,
    );
    if (vendas.isEmpty) throw StateError('Venda não encontrada.');
    final pagamentoId = _id('ppg');
    final movimentoId = _id('fin');
    final agora = _agora();
    await txn.insert('movimentacoes_financeiras', {
      'id': movimentoId,
      'comercio_id': _comercioId,
      'tipo': 'entrada',
      'descricao': 'Recebimento de pacote',
      'valor': valor,
      'forma_pagamento': formaPagamento,
      'status': 'pago',
      'data': agora,
      'data_criacao': agora,
      'categoria': 'Pacotes de serviços',
      'usuario_responsavel_id': _usuarioId,
      'observacoes': 'pacote_venda_id=$vendaId',
    });
    // pacote_pagamentos removed in Phase 1
    await txn.update(
      'pacotes_vendidos',
      {'updated_at': agora},
      where: 'id=? AND business_id=?',
      whereArgs: [vendaId, _comercioId],
    );
    await _auditar(
      txn,
      acao: 'pagamento_registrado',
      vendaId: vendaId,
      dados: {'valor': valor, 'pagamento_id': pagamentoId},
    );
  }

  Future<void> estornarPagamento(String pagamentoId) async {
    _exigir(AcaoPermissao.estornarPagamentoPacote);
    // Estorno handled via finance module in new schema
  }

  Future<List<ResumoVendaPacote>> listarVendas({String? clienteId}) async {
    _exigir(AcaoPermissao.visualizarPacotes);
    final db = await _databaseProvider();
    final rows = await db.rawQuery(
      '''SELECT v.*, p.nome AS pacote_nome, c.nome AS cliente_nome,
       SUM(CASE WHEN s.status='realizada' THEN 1 ELSE 0 END) realizadas,
       SUM(CASE WHEN s.status='agendada' THEN 1 ELSE 0 END) agendadas,
       SUM(CASE WHEN s.status='disponivel' THEN 1 ELSE 0 END) disponiveis,
       SUM(CASE WHEN s.status='cancelada' THEN 1 ELSE 0 END) canceladas,
       SUM(CASE WHEN s.status='vencida' THEN 1 ELSE 0 END) vencidas
       FROM pacotes_vendidos v
       JOIN pacotes p ON p.id=v.pacote_id
       JOIN clientes c ON c.id=v.cliente_id
       LEFT JOIN sessoes_pacotes s ON s.pacote_vendido_id=v.id
       WHERE v.business_id=? ${clienteId == null ? '' : 'AND v.cliente_id=?'}
       GROUP BY v.id ORDER BY v.data_venda DESC''',
      [_comercioId, if (clienteId != null) clienteId],
    );
    return rows.map((e) {
      int n(String campo) => (e[campo] as num? ?? 0).toInt();
      return ResumoVendaPacote(
        id: e['id'] as String,
        pacoteNome: e['pacote_nome'] as String,
        clienteNome: e['cliente_nome'] as String,
        valorContratado: (e['valor_final'] as num).toDouble(),
        valorPago: (e['valor_final'] as num).toDouble(),
        valorPendente: 0,
        contratadas: (e['quantidade_sessoes'] as num).toInt(),
        realizadas: n('realizadas'),
        agendadas: n('agendadas'),
        disponiveis: n('disponiveis'),
        canceladas: n('canceladas'),
        vencidas: n('vencidas'),
        validade: DateTime.parse(e['validade_fim'] as String),
        status: e['status'] as String,
      );
    }).toList();
  }

  Future<List<Map<String, Object?>>> listarSessoes(String vendaId) async {
    final db = await _databaseProvider();
    return db.rawQuery(
      '''SELECT ps.*, s.nome AS servico_nome, p.nome AS profissional_nome
         FROM sessoes_pacotes ps
         JOIN servicos s ON s.id=ps.servico_id_previsto
         LEFT JOIN profissionais p ON p.id=ps.profissional_id
         WHERE ps.business_id=? AND ps.pacote_vendido_id=?
         ORDER BY COALESCE(ps.ordem, 9999)''',
      [_comercioId, vendaId],
    );
  }

  Future<PreviaAgendaPacote> gerarPrevia(
    SolicitacaoAgendaPacote solicitacao,
  ) async {
    _exigir(AcaoPermissao.venderPacotes);
    final db = await _databaseProvider();
    final sessoes = await db.rawQuery(
      '''SELECT ps.*, s.nome AS servico_nome, pv.status AS venda_status,
         pv.validade_fim as validade_em, pv.pacote_id, 0 as intervalo_minimo_dias, pi.duracao_prevista as duracao_minutos, pi.id as pacote_item_id
         FROM sessoes_pacotes ps
         JOIN servicos s ON s.id=ps.servico_id_previsto
         JOIN pacotes_vendidos pv ON pv.id=ps.pacote_vendido_id
         JOIN pacote_itens pi ON pi.servico_id=ps.servico_id_previsto AND pi.pacote_id=pv.pacote_id
         WHERE ps.business_id=? AND ps.pacote_vendido_id=? AND ps.status='disponivel'
         ORDER BY COALESCE(ps.ordem, 9999), ps.id''',
      [_comercioId, solicitacao.vendaId],
    );
    if (sessoes.isEmpty) {
      return const PreviaAgendaPacote(sessoes: [], naoEncaixadas: []);
    }
    if (sessoes.first['venda_status'] != 'ativo') {
      throw StateError('O pacote precisa estar ativo para agendar.');
    }
    final profissional = await db.query(
      'profissionais',
      columns: ['id', 'nome'],
      where: 'id=? AND comercio_id=? AND ativo=1',
      whereArgs: [solicitacao.profissionalId, _comercioId],
      limit: 1,
    );
    if (profissional.isEmpty) throw StateError('Profissional indisponível.');
    final planejadas = <SessaoPlanejadaPacote>[];
    final falhas = <String>[];
    var alvo = solicitacao.primeiraData;
    DateTime? anterior;
    final agenda = AgendaCompletaRepository(
      databaseProvider: _databaseProvider,
      comercioId: _comercioId,
      usuarioId: _usuarioId,
    );
    for (final sessao in sessoes) {
      final autorizados = await db.query(
        'pacote_item_profissionais',
        columns: ['profissional_id'],
        where: 'comercio_id=? AND pacote_item_id=?',
        whereArgs: [_comercioId, sessao['pacote_item_id']],
      );
      if (autorizados.isNotEmpty &&
          !autorizados.any(
            (r) => r['profissional_id'] == solicitacao.profissionalId,
          )) {
        falhas.add('${sessao['servico_nome']}: profissional não autorizado.');
        continue;
      }
      if (anterior != null) {
        final minimo = sessao['intervalo_minimo_dias'] as int;
        final minimoData = anterior.add(Duration(days: minimo));
        if (alvo.isBefore(minimoData)) alvo = minimoData;
      }
      final desejado = _comHora(
        alvo,
        solicitacao.horaPreferida,
        solicitacao.minutoPreferido,
      );
      DateTime? escolhido;
      for (
        var deslocamento = 0;
        deslocamento <= solicitacao.limiteBuscaDias && escolhido == null;
        deslocamento++
      ) {
        final data = desejado.add(Duration(days: deslocamento));
        if (solicitacao.diasSemana.isNotEmpty &&
            !solicitacao.diasSemana.contains(data.weekday)) {
          continue;
        }
        if (data.isAfter(DateTime.parse(sessao['validade_em'] as String))) {
          break;
        }
        final livres = await agenda.horariosDisponiveis(
          profissionalId: solicitacao.profissionalId,
          data: data,
          duracaoMinutos: sessao['duracao_minutos'] as int,
        );
        livres.removeWhere(
          (inicio) => planejadas.any(
            (p) =>
                inicio.isBefore(p.fim) &&
                inicio
                    .add(Duration(minutes: sessao['duracao_minutos'] as int))
                    .isAfter(p.inicio),
          ),
        );
        if (livres.isNotEmpty) {
          livres.sort(
            (a, b) => a
                .difference(desejado)
                .abs()
                .compareTo(b.difference(desejado).abs()),
          );
          escolhido = livres.first;
        }
      }
      if (escolhido == null) {
        falhas.add('${sessao['servico_nome']}: nenhum horário compatível.');
        continue;
      }
      planejadas.add(
        SessaoPlanejadaPacote(
          sessaoId: sessao['id'] as String,
          servicoId: sessao['servico_id_previsto'] as String,
          servicoNome: sessao['servico_nome'] as String,
          profissionalId: solicitacao.profissionalId,
          profissionalNome: profissional.first['nome'] as String,
          inicio: escolhido,
          duracaoMinutos: sessao['duracao_minutos'] as int,
          horarioAlternativo:
              escolhido.day != desejado.day ||
              escolhido.hour != desejado.hour ||
              escolhido.minute != desejado.minute,
          aviso: escolhido == desejado
              ? null
              : 'Horário alternativo mais próximo.',
        ),
      );
      anterior = escolhido;
      alvo = _proximoAlvo(escolhido, solicitacao);
    }
    return PreviaAgendaPacote(sessoes: planejadas, naoEncaixadas: falhas);
  }

  Future<void> confirmarPrevia(PreviaAgendaPacote previa) async {
    _exigir(AcaoPermissao.venderPacotes);
    if (previa.sessoes.isEmpty) {
      throw StateError('Não há sessões para confirmar.');
    }
    final db = await _databaseProvider();
    await db.transaction((txn) async {
      for (final item in previa.sessoes) {
        final sessaoRows = await txn.rawQuery(
          '''SELECT ps.*, pv.cliente_id, pv.forma_pagamento, pv.status venda_status
             FROM sessoes_pacotes ps JOIN pacotes_vendidos pv
             ON pv.id=ps.pacote_vendido_id
             WHERE ps.id=? AND ps.business_id=? AND ps.status='disponivel' ''',
          [item.sessaoId, _comercioId],
        );
        if (sessaoRows.isEmpty || sessaoRows.first['venda_status'] != 'ativo') {
          throw StateError('A sessão mudou desde a prévia. Gere-a novamente.');
        }
        final conflitos = await txn.query(
          'agendamentos',
          columns: ['id'],
          where:
              "comercio_id=? AND profissional_id=? AND status!='cancelado' "
              'AND inicio<? AND fim>?',
          whereArgs: [
            _comercioId,
            item.profissionalId,
            item.fim.toIso8601String(),
            item.inicio.toIso8601String(),
          ],
          limit: 1,
        );
        final bloqueios = await txn.query(
          'bloqueios_agenda',
          columns: ['id'],
          where:
              'comercio_id=? AND (profissional_id IS NULL OR profissional_id=?) '
              'AND inicio<? AND fim>?',
          whereArgs: [
            _comercioId,
            item.profissionalId,
            item.fim.toIso8601String(),
            item.inicio.toIso8601String(),
          ],
          limit: 1,
        );
        if (conflitos.isNotEmpty || bloqueios.isNotEmpty) {
          throw StateError('Um horário da prévia não está mais disponível.');
        }
        final sessao = sessaoRows.first;
        final agendamentoId = _id('ag');
        await txn.insert('agendamentos', {
          'id': agendamentoId,
          'comercio_id': _comercioId,
          'cliente_id': sessao['cliente_id'],
          'profissional_id': item.profissionalId,
          'servico_id': item.servicoId,
          'inicio': item.inicio.toIso8601String(),
          'fim': item.fim.toIso8601String(),
          'status': 'agendado',
          'forma_pagamento': 'Pacote',
          'valor_servico': 0,
          'desconto': 0,
          'valor_recebido': 0,
          'confirmado': 0,
          'compareceu': 0,
          'observacoes': 'Sessão de pacote; receita registrada na venda.',
          'data_criacao': _agora(),
          'created_by': _usuarioId,
          'created_at': _agora(),
          'updated_at': _agora(),
        });
        await txn.update(
          'sessoes_pacotes',
          {
            'profissional_id': item.profissionalId,
            'agendamento_id': agendamentoId,
            'data_agendada': item.inicio.toIso8601String(),
            'status': 'agendada',
            'updated_at': _agora(),
          },
          where: 'id=? AND business_id=? AND status=?',
          whereArgs: [item.sessaoId, _comercioId, 'disponivel'],
        );
      }
      await _enfileirar(
        txn,
        'pacote_agenda',
        previa.sessoes.first.sessaoId,
        'criar',
      );
    });
  }

  Future<void> concluirAgendamentoPacote(String agendamentoId) async {
    _exigir(AcaoPermissao.baixarSessaoPacote);
    final db = await _databaseProvider();
    await db.transaction((txn) async {
      final rows = await txn.rawQuery(
        '''SELECT a.*, ps.id sessao_id, ps.pacote_vendido_id as pacote_venda_id, ps.status sessao_status,
           ps.estoque_consumido as credito_consumido, pv.valor_original as valor_contratado, pv.quantidade_sessoes as total_sessoes,
           s.comissao_percentual
           FROM agendamentos a
           JOIN sessoes_pacotes ps ON ps.agendamento_id=a.id
           JOIN pacotes_vendidos pv ON pv.id=ps.pacote_vendido_id
           JOIN pacotes p ON p.id=pv.pacote_id
           JOIN servicos s ON s.id=a.servico_id
           WHERE a.id=? AND a.comercio_id=?''',
        [agendamentoId, _comercioId],
      );
      if (rows.isEmpty) throw StateError('Sessão de pacote não encontrada.');
      final row = rows.first;
      if ((row['credito_consumido'] as num).toDouble() > 0) return;
      final materiais = await txn.query(
        'servico_materiais',
        where: 'comercio_id=? AND servico_id=? AND ativo=1',
        whereArgs: [_comercioId, row['servico_id']],
      );
      for (final material in materiais) {
        final estoques = await txn.query(
          'estoque',
          where: 'id=? AND comercio_id=?',
          whereArgs: [material['estoque_id'], _comercioId],
          limit: 1,
        );
        if (estoques.isEmpty ||
            (estoques.first['quantidade_atual'] as num).toDouble() <
                (material['quantidade'] as num).toDouble()) {
          throw StateError('Estoque insuficiente para concluir a sessão.');
        }
      }
      final agora = _agora();
      await txn.update(
        'agendamentos',
        {
          'status': 'concluido',
          'confirmado': 1,
          'compareceu': 1,
          'valor_recebido': 0,
          'updated_at': agora,
        },
        where: 'id=? AND comercio_id=?',
        whereArgs: [agendamentoId, _comercioId],
      );
      await txn.update(
        'sessoes_pacotes',
        {'status': 'realizada', 'estoque_consumido': 1, 'updated_at': agora},
        where: 'id=? AND business_id=? AND estoque_consumido=0',
        whereArgs: [row['sessao_id'], _comercioId],
      );
      for (final material in materiais) {
        final estoque = (await txn.query(
          'estoque',
          where: 'id=? AND comercio_id=?',
          whereArgs: [material['estoque_id'], _comercioId],
          limit: 1,
        )).first;
        final anterior = (estoque['quantidade_atual'] as num).toDouble();
        final quantidade = (material['quantidade'] as num).toDouble();
        await txn.update(
          'estoque',
          {'quantidade_atual': anterior - quantidade},
          where: 'id=? AND comercio_id=?',
          whereArgs: [material['estoque_id'], _comercioId],
        );
        await txn.insert('movimentacoes_estoque', {
          'id': _id('movest'),
          'comercio_id': _comercioId,
          'item_estoque_id': material['estoque_id'],
          'tipo': 'saida',
          'quantidade': quantidade,
          'quantidade_anterior': anterior,
          'quantidade_posterior': anterior - quantidade,
          'data': agora,
          'motivo': 'Material consumido em sessão de pacote',
          'agendamento_id': agendamentoId,
          'profissional_id': row['profissional_id'],
          'usuario_responsavel_id': _usuarioId,
        });
      }
      await _auditar(
        txn,
        acao: 'sessao_realizada',
        vendaId: row['pacote_venda_id'] as String,
        sessaoId: row['sessao_id'] as String,
        dados: {'agendamento_id': agendamentoId},
      );
    });
  }

  Future<void> registrarFalta(
    String agendamentoId, {
    bool aprovada = false,
  }) async {
    _exigir(AcaoPermissao.baixarSessaoPacote);
    final db = await _databaseProvider();
    await db.transaction((txn) async {
      final rows = await txn.rawQuery(
        '''SELECT ps.id as sessao_id, ps.pacote_vendido_id as pacote_venda_id
           FROM agendamentos a JOIN sessoes_pacotes ps
           ON ps.agendamento_id=a.id
           WHERE a.id=? AND a.comercio_id=?''',
        [agendamentoId, _comercioId],
      );
      if (rows.isEmpty) throw StateError('Sessão de pacote não encontrada.');
      final row = rows.first;
      await txn.update(
        'agendamentos',
        {'status': 'faltou', 'compareceu': 0, 'updated_at': _agora()},
        where: 'id=? AND comercio_id=?',
        whereArgs: [agendamentoId, _comercioId],
      );
      await txn.update(
        'sessoes_pacotes',
        {
          'status': 'faltou_consumida',
          'estoque_consumido': 1.0,
          'agendamento_id': agendamentoId,
          'updated_at': _agora(),
        },
        where: 'id=? AND business_id=?',
        whereArgs: [row['sessao_id'], _comercioId],
      );
      await _auditar(
        txn,
        acao: 'falta_registrada',
        vendaId: row['pacote_venda_id'] as String,
        sessaoId: row['sessao_id'] as String,
        dados: {'credito_consumido': 1.0},
      );
    });
  }

  Future<void> reagendarSessoes({
    required String sessaoId,
    required DateTime novoInicio,
    required String profissionalId,
    EscopoReagendamentoPacote escopo = EscopoReagendamentoPacote.somenteEsta,
  }) async {
    _exigir(AcaoPermissao.venderPacotes);
    final db = await _databaseProvider();
    await db.transaction((txn) async {
      final origemRows = await txn.query(
        'sessoes_pacotes',
        where: 'id=? AND business_id=? AND status=?',
        whereArgs: [sessaoId, _comercioId, 'agendada'],
        limit: 1,
      );
      if (origemRows.isEmpty) {
        throw StateError('Sessão agendada não encontrada.');
      }
      final origem = origemRows.first;
      final inicioOriginal = DateTime.parse(origem['data_agendada'] as String);
      final delta = novoInicio.difference(inicioOriginal);
      final selecionadas = await txn.query(
        'sessoes_pacotes',
        where: escopo == EscopoReagendamentoPacote.somenteEsta
            ? 'id=? AND business_id=?'
            : "pacote_vendido_id=? AND business_id=? AND status='agendada' AND ordem>=?",
        whereArgs: escopo == EscopoReagendamentoPacote.somenteEsta
            ? [sessaoId, _comercioId]
            : [origem['pacote_vendido_id'], _comercioId, origem['ordem']],
        orderBy: 'ordem',
      );
      final idsAgendamento = selecionadas
          .map((r) => r['agendamento_id'] as String?)
          .whereType<String>()
          .toList();
      for (final sessao in selecionadas) {
        final atual = DateTime.parse(sessao['data_agendada'] as String);
        final inicio = atual.add(delta);
        final fim = inicio.add(const Duration(minutes: 60));
        final jornada = await txn.query(
          'horarios_profissionais',
          where:
              'comercio_id=? AND profissional_id=? AND dia_semana=? AND ativo=1',
          whereArgs: [_comercioId, profissionalId, inicio.weekday],
          limit: 1,
        );
        if (jornada.isEmpty || !_dentroDaJornada(inicio, fim, jornada.first)) {
          throw StateError('Novo horário fora da jornada ou do intervalo.');
        }
        var where =
            "comercio_id=? AND profissional_id=? AND status!='cancelado' AND inicio<? AND fim>?";
        final args = <Object?>[
          _comercioId,
          profissionalId,
          fim.toIso8601String(),
          inicio.toIso8601String(),
        ];
        if (idsAgendamento.isNotEmpty) {
          where +=
              ' AND id NOT IN (${List.filled(idsAgendamento.length, '?').join(',')})';
          args.addAll(idsAgendamento);
        }
        final conflito = await txn.query(
          'agendamentos',
          columns: ['id'],
          where: where,
          whereArgs: args,
          limit: 1,
        );
        final bloqueio = await txn.query(
          'bloqueios_agenda',
          columns: ['id'],
          where:
              'comercio_id=? AND (profissional_id IS NULL OR profissional_id=?) AND inicio<? AND fim>?',
          whereArgs: [
            _comercioId,
            profissionalId,
            fim.toIso8601String(),
            inicio.toIso8601String(),
          ],
          limit: 1,
        );
        if (conflito.isNotEmpty || bloqueio.isNotEmpty) {
          final agenda = AgendaCompletaRepository(
            databaseProvider: _databaseProvider,
            comercioId: _comercioId,
            usuarioId: _usuarioInformado,
          );
          final duracaoMinutos = fim.difference(inicio).inMinutes;
          final alternativas = await agenda.horariosDisponiveis(
            profissionalId: profissionalId,
            data: inicio,
            duracaoMinutos: duracaoMinutos,
          );
          throw ConflitoAgendaException(
            'O reagendamento produziria conflito.',
            alternativas,
          );
        }
        await txn.update(
          'agendamentos',
          {
            'profissional_id': profissionalId,
            'inicio': inicio.toIso8601String(),
            'fim': fim.toIso8601String(),
            'status': 'agendado',
            'confirmado': 0,
            'updated_at': _agora(),
          },
          where: 'id=? AND comercio_id=?',
          whereArgs: [sessao['agendamento_id'], _comercioId],
        );
        await txn.update(
          'sessoes_pacotes',
          {
            'profissional_id': profissionalId,
            'data_agendada': inicio.toIso8601String(),
            'updated_at': _agora(),
          },
          where: 'id=? AND business_id=?',
          whereArgs: [sessao['id'], _comercioId],
        );
      }
      await _auditar(
        txn,
        acao: 'sessoes_reagendadas',
        vendaId: origem['pacote_vendido_id'] as String,
        sessaoId: sessaoId,
        dados: {'escopo': escopo.name, 'quantidade': selecionadas.length},
      );
      await _enfileirar(txn, 'pacote_agenda', sessaoId, 'editar');
    });
  }

  bool _dentroDaJornada(
    DateTime inicio,
    DateTime fim,
    Map<String, Object?> jornada,
  ) {
    DateTime emData(String horario) {
      final partes = horario.split(':');
      return DateTime(
        inicio.year,
        inicio.month,
        inicio.day,
        int.parse(partes[0]),
        int.parse(partes[1]),
      );
    }

    final abertura = emData(jornada['inicio'] as String);
    final fechamento = emData(jornada['fim'] as String);
    if (inicio.isBefore(abertura) || fim.isAfter(fechamento)) return false;
    if (jornada['intervalo_inicio'] != null &&
        jornada['intervalo_fim'] != null) {
      final pausaInicio = emData(jornada['intervalo_inicio'] as String);
      final pausaFim = emData(jornada['intervalo_fim'] as String);
      if (inicio.isBefore(pausaFim) && fim.isAfter(pausaInicio)) return false;
    }
    return true;
  }

  Future<void> cancelarAgendamentoPacote(String agendamentoId) async {
    final db = await _databaseProvider();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'sessoes_pacotes',
        columns: ['id'],
        where: 'agendamento_id=? AND business_id=?',
        whereArgs: [agendamentoId, _comercioId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      await txn.update(
        'sessoes_pacotes',
        {
          'status': 'disponivel',
          'agendamento_id': null,
          'data_agendada': null,
          'profissional_id': null,
          'updated_at': _agora(),
        },
        where: 'id=? AND business_id=? AND estoque_consumido=0',
        whereArgs: [rows.first['id'], _comercioId],
      );
    });
  }

  Future<void> alterarStatusVenda(
    String vendaId,
    String status, {
    String motivo = '',
  }) async {
    if (status == 'cancelado') _exigir(AcaoPermissao.cancelarPacote);
    if (status == 'pausado' || status == 'ativo') {
      _exigir(AcaoPermissao.editarPacotes);
    }
    if (!{'ativo', 'pausado', 'cancelado'}.contains(status)) {
      throw ArgumentError('Status inválido.');
    }
    final db = await _databaseProvider();
    await db.update(
      'pacotes_vendidos',
      {
        'status': status,
        'observacoes': status == 'cancelado' ? motivo : null,
        'updated_at': _agora(),
      },
      where: 'id=? AND business_id=?',
      whereArgs: [vendaId, _comercioId],
    );
  }

  Future<void> estenderValidade(String vendaId, int dias) async {
    _exigir(AcaoPermissao.alterarValidadePacote);
    if (dias <= 0) throw ArgumentError('Informe dias adicionais.');
    final db = await _databaseProvider();
    final rows = await db.query(
      'pacotes_vendidos',
      columns: ['validade_fim'],
      where: 'id=? AND business_id=?',
      whereArgs: [vendaId, _comercioId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Venda não encontrada.');
    final validade = DateTime.parse(
      rows.first['validade_fim'] as String,
    ).add(Duration(days: dias));
    await db.update(
      'pacotes_vendidos',
      {'validade_fim': validade.toIso8601String(), 'updated_at': _agora()},
      where: 'id=? AND business_id=?',
      whereArgs: [vendaId, _comercioId],
    );
  }

  Future<void> transferir(String vendaId, String novoClienteId) async {
    _exigir(AcaoPermissao.transferirPacote);
    final db = await _databaseProvider();
    await db.transaction((txn) async {
      final vendas = await txn.rawQuery(
        '''SELECT v.* FROM pacotes_vendidos v
           JOIN pacotes p ON p.id=v.pacote_id
           WHERE v.id=? AND v.business_id=?''',
        [vendaId, _comercioId],
      );
      if (vendas.isEmpty || vendas.first['status'] != 'ativo') {
        throw StateError('Venda não encontrada ou pacote não está ativo.');
      }
      final cliente = await txn.query(
        'clientes',
        columns: ['id'],
        where: 'id=? AND comercio_id=? AND ativo=1',
        whereArgs: [novoClienteId, _comercioId],
        limit: 1,
      );
      if (cliente.isEmpty) throw StateError('Cliente de destino inválido.');
      await txn.update(
        'pacotes_vendidos',
        {
          'observacoes': 'Transferido de ${vendas.first['cliente_id']}',
          'cliente_id': novoClienteId,
          'updated_at': _agora(),
        },
        where: 'id=? AND business_id=?',
        whereArgs: [vendaId, _comercioId],
      );
      await _auditar(
        txn,
        acao: 'pacote_transferido',
        vendaId: vendaId,
        dados: {'novo_cliente_id': novoClienteId},
      );
    });
  }

  Future<void> salvarMateriaisServico(
    String servicoId,
    Map<String, double> materiais,
  ) async {
    _exigir(AcaoPermissao.editarPacotes);
    if (materiais.values.any((q) => q <= 0)) {
      throw ArgumentError('Quantidade de material inválida.');
    }
    final db = await _databaseProvider();
    await db.transaction((txn) async {
      await txn.delete(
        'servico_materiais',
        where: 'comercio_id=? AND servico_id=?',
        whereArgs: [_comercioId, servicoId],
      );
      for (final item in materiais.entries) {
        await txn.insert('servico_materiais', {
          'id': _id('smat'),
          'comercio_id': _comercioId,
          'servico_id': servicoId,
          'estoque_id': item.key,
          'quantidade': item.value,
          'ativo': 1,
        });
      }
    });
  }

  Future<Map<String, Object?>> relatorio({
    DateTime? inicio,
    DateTime? fim,
  }) async {
    _exigir(AcaoPermissao.consultarRelatoriosPacotes);
    final db = await _databaseProvider();
    final de = (inicio ?? DateTime(2000)).toIso8601String();
    final ate = (fim ?? DateTime(2100)).toIso8601String();
    final vendas = await db.rawQuery(
      '''SELECT COUNT(*) quantidade, COALESCE(SUM(valor_original),0) vendido,
         COALESCE(SUM(valor_final),0) recebido, 0 pendente
         FROM pacotes_vendidos WHERE business_id=? AND data_venda BETWEEN ? AND ?''',
      [_comercioId, de, ate],
    );
    final sessoes = await db.rawQuery(
      '''SELECT status, COUNT(*) quantidade FROM sessoes_pacotes
         WHERE business_id=? GROUP BY status''',
      [_comercioId],
    );
    return {'vendas': vendas.first, 'sessoes': sessoes};
  }

  Future<List<Map<String, Object?>>> listarAlertas() async {
    _exigir(AcaoPermissao.visualizarPacotes);
    final db = await _databaseProvider();
    return db.rawQuery(
      '''SELECT a.*, p.nome AS pacote_nome, c.nome AS cliente_nome
         FROM pacote_alertas a
         JOIN pacotes_vendidos v ON v.id=a.pacote_venda_id
         JOIN pacotes p ON p.id=v.pacote_id
         JOIN clientes c ON c.id=v.cliente_id
         WHERE a.comercio_id=? AND a.status='pendente'
         ORDER BY a.criado_em DESC''',
      [_comercioId],
    );
  }

  Future<int> gerarAlertas() async {
    final db = await _databaseProvider();
    var criados = 0;
    final agora = DateTime.now();
    final vendas = await db.query(
      'pacotes_vendidos',
      where: "business_id=? AND status IN ('ativo','pausado')",
      whereArgs: [_comercioId],
    );
    for (final venda in vendas) {
      final validade = DateTime.parse(venda['validade_fim'] as String);
      final diferenca = validade.difference(agora).inDays;
      if (validade.isBefore(agora)) {
        await db.update(
          'pacotes_vendidos',
          {'status': 'vencido', 'updated_at': _agora()},
          where: 'id=? AND business_id=?',
          whereArgs: [venda['id'], _comercioId],
        );
        await db.update(
          'sessoes_pacotes',
          {'status': 'vencida', 'updated_at': _agora()},
          where:
              "pacote_vendido_id=? AND business_id=? AND status='disponivel'",
          whereArgs: [venda['id'], _comercioId],
        );
      }
      final alertas = <Map<String, String>>[];
      if (diferenca <= 7) {
        alertas.add({
          'tipo': diferenca < 0 ? 'pacote_vencido' : 'validade_proxima',
          'mensagem': diferenca < 0
              ? 'Pacote vencido com sessões pendentes.'
              : 'Pacote vence em até 7 dias.',
        });
      }
      // valor_pendente now handled by finance
      for (final alerta in alertas) {
        final result = await db.insert('pacote_alertas', {
          'id': _id('palt'),
          'comercio_id': _comercioId,
          'pacote_venda_id': venda['id'],
          'tipo': alerta['tipo'],
          'mensagem': alerta['mensagem'],
          'canal': 'app',
          'status': 'pendente',
          'referencia_data': DateTime(
            agora.year,
            agora.month,
            agora.day,
          ).toIso8601String(),
          'criado_em': _agora(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        if (result > 0) criados++;
      }
    }
    return criados;
  }

  Future<void> _comissao(
    DatabaseExecutor txn, {
    required String vendaId,
    String? sessaoId,
    required String profissionalId,
    required String papel,
    required double base,
    required double percentual,
  }) async {
    if (percentual <= 0) return;
    final existente = await txn.query(
      'pacote_comissoes',
      columns: ['id'],
      where:
          'comercio_id=? AND pacote_venda_id=? AND '
          '${sessaoId == null ? 'sessao_id IS NULL' : 'sessao_id=?'} '
          'AND profissional_id=? AND papel=?',
      whereArgs: [_comercioId, vendaId, ?sessaoId, profissionalId, papel],
      limit: 1,
    );
    if (existente.isNotEmpty) return;
    await txn.insert('pacote_comissoes', {
      'id': _id('pcom'),
      'comercio_id': _comercioId,
      'pacote_venda_id': vendaId,
      'sessao_id': sessaoId,
      'profissional_id': profissionalId,
      'papel': papel,
      'valor_base': base,
      'percentual': percentual,
      'valor_comissao': base * percentual / 100,
      'status': 'pendente',
      'criada_em': _agora(),
    });
  }

  Future<void> _auditar(
    DatabaseExecutor txn, {
    required String acao,
    String? vendaId,
    String? pacoteId,
    String? sessaoId,
    Map<String, Object?> dados = const {},
  }) {
    return txn.insert('pacote_auditoria', {
      'id': _id('paud'),
      'comercio_id': _comercioId,
      'pacote_venda_id': vendaId,
      'pacote_id': pacoteId,
      'sessao_id': sessaoId,
      'usuario_id': _usuarioId,
      'acao': acao,
      'dados_json': jsonEncode(dados),
      'criado_em': _agora(),
    });
  }

  Future<void> _enfileirar(
    DatabaseExecutor txn,
    String entidade,
    String entidadeId,
    String operacao,
  ) {
    final agora = _agora();
    return txn.insert('fila_sincronizacao', {
      'id': _id('sync'),
      'comercio_id': _comercioId,
      'entidade': entidade,
      'entidade_id': entidadeId,
      'operacao': operacao,
      'payload_json': jsonEncode({'id': entidadeId}),
      'versao_local': 1,
      'status': 'pendente',
      'tentativas': 0,
      'criada_em': agora,
      'atualizada_em': agora,
    });
  }

  Future<void> editarSessaoVendida({
    required String sessaoId,
    required DateTime novoInicio,
    required String novoServicoId,
    required String novoProfissionalId,
  }) async {
    _exigir(AcaoPermissao.venderPacotes);
    final db = await _databaseProvider();

    await db.transaction((txn) async {
      final sessaoRow = await txn.query(
        'sessoes_pacotes',
        where: 'id=? AND business_id=? AND status=?',
        whereArgs: [sessaoId, _comercioId, 'agendada'],
      );

      if (sessaoRow.isEmpty) {
        throw StateError('Sessão agendada não encontrada ou já realizada.');
      }

      final sessao = sessaoRow.first;
      final agendamentoId = sessao['agendamento_id'] as String?;

      if (agendamentoId == null) {
        throw StateError('Agendamento vinculado não encontrado.');
      }

      final agendamentoRow = await txn.query(
        'agendamentos',
        where: 'id=? AND comercio_id=?',
        whereArgs: [agendamentoId, _comercioId],
      );

      if (agendamentoRow.isEmpty) {
        throw StateError('Agendamento vinculado não encontrado.');
      }

      final agendamentoAntigo = agendamentoRow.first;
      final duracao = DateTime.parse(
        agendamentoAntigo['fim'] as String,
      ).difference(DateTime.parse(agendamentoAntigo['inicio'] as String));

      final novoFim = novoInicio.add(duracao);

      // We should check the agenda for conflicts using AgendaConflictChecker!
      // For this, we can fetch all appointments for that professional on the day,
      // and use the checker. Since this is an individual reschedule, AgendaConflictChecker
      // can be called manually here, or we can use the same logic as AgendaRepository.atualizar().

      // Validação de jornada
      final jornada = await txn.query(
        'horarios_profissionais',
        where:
            'comercio_id=? AND profissional_id=? AND dia_semana=? AND ativo=1',
        whereArgs: [_comercioId, novoProfissionalId, novoInicio.weekday],
      );
      if (jornada.isEmpty ||
          !_dentroDaJornada(novoInicio, novoFim, jornada.first)) {
        throw StateError('Novo horário fora da jornada do profissional.');
      }

      // Validação de conflito
      final conflito = await txn.query(
        'agendamentos',
        where:
            "comercio_id=? AND profissional_id=? AND status!='cancelado' AND inicio<? AND fim>? AND id!=?",
        whereArgs: [
          _comercioId,
          novoProfissionalId,
          novoFim.toIso8601String(),
          novoInicio.toIso8601String(),
          agendamentoId,
        ],
      );
      if (conflito.isNotEmpty) {
        throw StateError('Já existe um agendamento nesse horário.');
      }

      await txn.update(
        'sessoes_pacotes',
        {
          'servico_id_previsto': novoServicoId,
          'servico_id_realizado': novoServicoId,
          'profissional_id': novoProfissionalId,
          'data_agendada': novoInicio.toIso8601String(),
          'horario_inicio':
              '${novoInicio.hour.toString().padLeft(2, '0')}:${novoInicio.minute.toString().padLeft(2, '0')}',
          'horario_fim':
              '${novoFim.hour.toString().padLeft(2, '0')}:${novoFim.minute.toString().padLeft(2, '0')}',
          'updated_at': _agora(),
        },
        where: 'id=?',
        whereArgs: [sessaoId],
      );

      await txn.update(
        'agendamentos',
        {
          'servico_id': novoServicoId,
          'profissional_id': novoProfissionalId,
          'inicio': novoInicio.toIso8601String(),
          'fim': novoFim.toIso8601String(),
          'updated_at': _agora(),
        },
        where: 'id=? AND comercio_id=?',
        whereArgs: [agendamentoId, _comercioId],
      );
    });
  }

  String _modoComissao(ModoComissaoPacote modo) {
    return switch (modo) {
      ModoComissaoPacote.venda => 'venda',
      ModoComissaoPacote.porSessao => 'por_sessao',
      ModoComissaoPacote.dividida => 'dividida',
    };
  }

  DateTime _comHora(DateTime data, int hora, int minuto) =>
      DateTime(data.year, data.month, data.day, hora, minuto);

  DateTime _proximoAlvo(DateTime atual, SolicitacaoAgendaPacote solicitacao) {
    return switch (solicitacao.frequencia) {
      FrequenciaAgendamentoPacote.dias => atual.add(
        Duration(days: solicitacao.intervalo),
      ),
      FrequenciaAgendamentoPacote.semanal => atual.add(
        Duration(days: 7 * solicitacao.intervalo),
      ),
      FrequenciaAgendamentoPacote.mensal => DateTime(
        atual.year,
        atual.month + solicitacao.intervalo,
        atual.day,
        atual.hour,
        atual.minute,
      ),
    };
  }
}
