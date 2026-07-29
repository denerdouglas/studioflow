import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../models/domain/acesso.dart';
import '../models/domain/pacote_servico.dart';
import '../services/session_controller.dart';
import 'agenda_completa_repository.dart';

class PacotesRepository {
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
        (SELECT GROUP_CONCAT(s.nome || ' ×' || i.quantidade, ', ')
         FROM pacote_servico_itens i
         JOIN servicos s ON s.id=i.servico_id
         WHERE i.pacote_id=p.id) AS itens_resumo
       FROM pacotes_servicos p
       WHERE p.comercio_id=? ${incluirInativos ? '' : 'AND p.ativo=1'}
       ORDER BY p.ativo DESC, p.nome COLLATE NOCASE''',
      [_comercioId],
    );
  }

  Future<List<Map<String, Object?>>> listarItens(String pacoteId) async {
    final db = await _databaseProvider();
    return db.rawQuery(
      '''SELECT i.*, s.nome AS servico_nome
         FROM pacote_servico_itens i
         JOIN servicos s ON s.id=i.servico_id
         WHERE i.comercio_id=? AND i.pacote_id=?
         ORDER BY COALESCE(i.ordem_inicial, 9999), s.nome''',
      [_comercioId, pacoteId],
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
        'comercio_id': _comercioId,
        'nome': entrada.nome.trim(),
        'descricao': entrada.descricao.trim(),
        'categoria': entrada.categoria.trim(),
        'tipo_sequencia': entrada.tipoSequencia.name,
        'total_sessoes': totalSessoes,
        'preco_individual_somado': soma,
        'preco_pacote': entrada.precoPacote,
        'desconto': (soma - entrada.precoPacote).clamp(0, double.infinity),
        'validade_dias': entrada.validadeDias,
        'intervalo_recomendado_dias': entrada.intervaloRecomendadoDias,
        'forma_pagamento_padrao': entrada.formaPagamentoPadrao,
        'permite_parcelamento': entrada.permiteParcelamento ? 1 : 0,
        'max_parcelas': entrada.maxParcelas,
        'exige_sinal': entrada.exigeSinal ? 1 : 0,
        'sinal_padrao': entrada.sinalPadrao,
        'regras_cancelamento': entrada.regrasCancelamento.trim(),
        'regra_falta': _regraFalta(entrada.regraFalta),
        'percentual_falta': entrada.percentualFalta,
        'permite_transferencia': entrada.permiteTransferencia ? 1 : 0,
        'modo_comissao': _modoComissao(entrada.modoComissao),
        'percentual_vendedor': entrada.percentualVendedor,
        'observacoes': entrada.observacoes.trim(),
        'ativo': entrada.ativo ? 1 : 0,
        'criado_por_id': _usuarioId,
        'criado_em': agora,
        'atualizado_em': agora,
      };
      if (entrada.id == null) {
        await txn.insert('pacotes_servicos', mapa);
      } else {
        mapa.remove('id');
        mapa.remove('comercio_id');
        mapa.remove('criado_em');
        await txn.update(
          'pacotes_servicos',
          mapa,
          where: 'id=? AND comercio_id=?',
          whereArgs: [id, _comercioId],
        );
        await txn.delete(
          'pacote_item_profissionais',
          where:
              'pacote_item_id IN (SELECT id FROM pacote_servico_itens '
              'WHERE pacote_id=? AND comercio_id=?)',
          whereArgs: [id, _comercioId],
        );
        await txn.delete(
          'pacote_servico_itens',
          where: 'pacote_id=? AND comercio_id=?',
          whereArgs: [id, _comercioId],
        );
      }
      for (final item in entrada.itens) {
        final servico = servicos[item.servicoId]!;
        final itemId = _id('pitem');
        await txn.insert('pacote_servico_itens', {
          'id': itemId,
          'comercio_id': _comercioId,
          'pacote_id': id,
          'servico_id': item.servicoId,
          'quantidade': item.quantidade,
          'ordem_inicial': item.ordemInicial,
          'intervalo_minimo_dias': item.intervaloMinimoDias,
          'intervalo_maximo_dias': item.intervaloMaximoDias,
          'duracao_minutos': item.duracaoMinutos ?? servico['duracao_minutos'],
          'preco_unitario_referencia': servico['preco'],
        });
        for (final profissionalId in item.profissionaisAutorizados) {
          final profissional = await txn.query(
            'profissionais',
            columns: ['id'],
            where: 'id=? AND comercio_id=? AND ativo=1',
            whereArgs: [profissionalId, _comercioId],
            limit: 1,
          );
          if (profissional.isEmpty) {
            throw StateError('Profissional autorizado inválido.');
          }
          await txn.insert('pacote_item_profissionais', {
            'comercio_id': _comercioId,
            'pacote_item_id': itemId,
            'profissional_id': profissionalId,
          });
        }
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
      'pacotes_servicos',
      {'ativo': ativo ? 1 : 0, 'atualizado_em': _agora()},
      where: 'id=? AND comercio_id=?',
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
        'pacotes_servicos',
        where: 'id=? AND comercio_id=? AND ativo=1',
        whereArgs: [entrada.pacoteId, _comercioId],
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
      final preco = (pacote['preco_pacote'] as num).toDouble();
      if (entrada.desconto < 0 || entrada.desconto > preco) {
        throw ArgumentError('Desconto inválido.');
      }
      final contratado = preco - entrada.desconto;
      final pago = entrada.valorPagoInicial;
      if (pago < 0 || pago > contratado) {
        throw ArgumentError('Pagamento inválido.');
      }
      if ((pacote['exige_sinal'] as int) == 1 &&
          entrada.sinal < (pacote['sinal_padrao'] as num).toDouble()) {
        throw StateError('O sinal mínimo do pacote não foi atendido.');
      }
      final permiteParcelar = (pacote['permite_parcelamento'] as int) == 1;
      if (entrada.parcelas > 1 && !permiteParcelar) {
        throw StateError('Este pacote não permite parcelamento.');
      }
      if (entrada.parcelas < 1 ||
          entrada.parcelas > (pacote['max_parcelas'] as int)) {
        throw ArgumentError('Quantidade de parcelas inválida.');
      }
      final compra = entrada.dataCompra;
      final validade = compra.add(
        Duration(days: pacote['validade_dias'] as int),
      );
      final agora = _agora();
      await txn.insert('pacote_vendas', {
        'id': vendaId,
        'comercio_id': _comercioId,
        'pacote_id': entrada.pacoteId,
        'cliente_id': entrada.clienteId,
        'vendedor_profissional_id': entrada.vendedorProfissionalId,
        'valor_contratado': contratado,
        'desconto_autorizado': entrada.desconto,
        'valor_pago': 0,
        'valor_pendente': contratado,
        'sinal': entrada.sinal,
        'forma_pagamento': entrada.formaPagamento,
        'quantidade_parcelas': entrada.parcelas,
        'total_sessoes': pacote['total_sessoes'],
        'data_compra': compra.toIso8601String(),
        'validade_em': validade.toIso8601String(),
        'status': 'ativo',
        'comanda_referencia': entrada.comandaReferencia,
        'criado_por_id': _usuarioId,
        'atualizado_em': agora,
      });
      final itens = await txn.query(
        'pacote_servico_itens',
        where: 'pacote_id=? AND comercio_id=?',
        whereArgs: [entrada.pacoteId, _comercioId],
        orderBy: 'COALESCE(ordem_inicial, 9999), id',
      );
      var numero = 0;
      for (final item in itens) {
        for (var i = 0; i < (item['quantidade'] as int); i++) {
          numero++;
          await txn.insert('pacote_venda_sessoes', {
            'id': _id('pvs'),
            'comercio_id': _comercioId,
            'pacote_venda_id': vendaId,
            'pacote_item_id': item['id'],
            'servico_id': item['servico_id'],
            'numero': numero,
            'ordem': item['ordem_inicial'] == null
                ? null
                : (item['ordem_inicial'] as int) + i,
            'duracao_minutos': item['duracao_minutos'],
            'intervalo_minimo_dias': item['intervalo_minimo_dias'],
            'intervalo_maximo_dias': item['intervalo_maximo_dias'],
            'status': 'disponivel',
            'credito_consumido': 0,
            'atualizado_em': agora,
          });
        }
      }
      final saldo = contratado - pago;
      final valorParcela = entrada.parcelas == 0
          ? saldo
          : saldo / entrada.parcelas;
      for (var i = 1; i <= entrada.parcelas; i++) {
        await txn.insert('pacote_parcelas', {
          'id': _id('ppar'),
          'comercio_id': _comercioId,
          'pacote_venda_id': vendaId,
          'numero': i,
          'valor': valorParcela,
          'vencimento': DateTime(
            compra.year,
            compra.month + i,
            compra.day,
          ).toIso8601String(),
          'status': saldo == 0 ? 'paga' : 'pendente',
          'paga_em': saldo == 0 ? agora : null,
        });
      }
      if (pago > 0) {
        await _registrarPagamentoTxn(
          txn,
          vendaId: vendaId,
          valor: pago,
          formaPagamento: entrada.formaPagamento,
        );
      }
      final modo = pacote['modo_comissao'] as String;
      if ((modo == 'venda' || modo == 'dividida') &&
          (pacote['percentual_vendedor'] as num).toDouble() > 0) {
        await _comissao(
          txn,
          vendaId: vendaId,
          profissionalId: entrada.vendedorProfissionalId,
          papel: 'vendedor',
          base: contratado,
          percentual: (pacote['percentual_vendedor'] as num).toDouble(),
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
      'pacote_vendas',
      where: 'id=? AND comercio_id=?',
      whereArgs: [vendaId, _comercioId],
      limit: 1,
    );
    if (vendas.isEmpty) throw StateError('Venda não encontrada.');
    final venda = vendas.first;
    final pendente = (venda['valor_pendente'] as num).toDouble();
    if (valor > pendente + 0.001) {
      throw StateError('Pagamento maior que o saldo.');
    }
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
      'cliente_id': venda['cliente_id'],
      'profissional_id': venda['vendedor_profissional_id'],
      'usuario_responsavel_id': _usuarioId,
      'observacoes': 'pacote_venda_id=$vendaId',
    });
    await txn.insert('pacote_pagamentos', {
      'id': pagamentoId,
      'comercio_id': _comercioId,
      'pacote_venda_id': vendaId,
      'valor': valor,
      'forma_pagamento': formaPagamento,
      'status': 'confirmado',
      'movimento_financeiro_id': movimentoId,
      'recebido_por_id': _usuarioId,
      'recebido_em': agora,
    });
    await txn.update(
      'pacote_vendas',
      {
        'valor_pago': (venda['valor_pago'] as num).toDouble() + valor,
        'valor_pendente': (pendente - valor).clamp(0, double.infinity),
        'atualizado_em': agora,
      },
      where: 'id=? AND comercio_id=?',
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
    final db = await _databaseProvider();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'pacote_pagamentos',
        where: 'id=? AND comercio_id=? AND status=?',
        whereArgs: [pagamentoId, _comercioId, 'confirmado'],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Pagamento não encontrado ou já estornado.');
      }
      final p = rows.first;
      final valor = (p['valor'] as num).toDouble();
      final vendas = await txn.query(
        'pacote_vendas',
        where: 'id=? AND comercio_id=?',
        whereArgs: [p['pacote_venda_id'], _comercioId],
        limit: 1,
      );
      final venda = vendas.first;
      final agora = _agora();
      await txn.update(
        'pacote_pagamentos',
        {'status': 'estornado', 'estornado_em': agora},
        where: 'id=?',
        whereArgs: [pagamentoId],
      );
      await txn.update(
        'movimentacoes_financeiras',
        {
          'status': 'cancelado',
          'observacoes': 'Estorno: pagamento $pagamentoId',
        },
        where: 'id=? AND comercio_id=?',
        whereArgs: [p['movimento_financeiro_id'], _comercioId],
      );
      await txn.update(
        'pacote_vendas',
        {
          'valor_pago': ((venda['valor_pago'] as num).toDouble() - valor).clamp(
            0,
            double.infinity,
          ),
          'valor_pendente': (venda['valor_pendente'] as num).toDouble() + valor,
          'atualizado_em': agora,
        },
        where: 'id=? AND comercio_id=?',
        whereArgs: [p['pacote_venda_id'], _comercioId],
      );
      await _auditar(
        txn,
        acao: 'pagamento_estornado',
        vendaId: p['pacote_venda_id'] as String,
        dados: {'pagamento_id': pagamentoId, 'valor': valor},
      );
    });
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
       FROM pacote_vendas v
       JOIN pacotes_servicos p ON p.id=v.pacote_id
       JOIN clientes c ON c.id=v.cliente_id
       LEFT JOIN pacote_venda_sessoes s ON s.pacote_venda_id=v.id
       WHERE v.comercio_id=? ${clienteId == null ? '' : 'AND v.cliente_id=?'}
       GROUP BY v.id ORDER BY v.data_compra DESC''',
      [_comercioId, ?clienteId],
    );
    return rows.map((e) {
      int n(String campo) => (e[campo] as num? ?? 0).toInt();
      return ResumoVendaPacote(
        id: e['id'] as String,
        pacoteNome: e['pacote_nome'] as String,
        clienteNome: e['cliente_nome'] as String,
        valorContratado: (e['valor_contratado'] as num).toDouble(),
        valorPago: (e['valor_pago'] as num).toDouble(),
        valorPendente: (e['valor_pendente'] as num).toDouble(),
        contratadas: (e['total_sessoes'] as num).toInt(),
        realizadas: n('realizadas'),
        agendadas: n('agendadas'),
        disponiveis: n('disponiveis'),
        canceladas: n('canceladas'),
        vencidas: n('vencidas'),
        validade: DateTime.parse(e['validade_em'] as String),
        status: e['status'] as String,
      );
    }).toList();
  }

  Future<List<Map<String, Object?>>> listarSessoes(String vendaId) async {
    final db = await _databaseProvider();
    return db.rawQuery(
      '''SELECT ps.*, s.nome AS servico_nome, p.nome AS profissional_nome
         FROM pacote_venda_sessoes ps
         JOIN servicos s ON s.id=ps.servico_id
         LEFT JOIN profissionais p ON p.id=ps.profissional_id
         WHERE ps.comercio_id=? AND ps.pacote_venda_id=?
         ORDER BY ps.numero''',
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
         pv.validade_em, pv.pacote_id
         FROM pacote_venda_sessoes ps
         JOIN servicos s ON s.id=ps.servico_id
         JOIN pacote_vendas pv ON pv.id=ps.pacote_venda_id
         WHERE ps.comercio_id=? AND ps.pacote_venda_id=? AND ps.status='disponivel'
         ORDER BY COALESCE(ps.ordem, ps.numero), ps.numero''',
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
          servicoId: sessao['servico_id'] as String,
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
             FROM pacote_venda_sessoes ps JOIN pacote_vendas pv
             ON pv.id=ps.pacote_venda_id
             WHERE ps.id=? AND ps.comercio_id=? AND ps.status='disponivel' ''',
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
          'atualizado_em': _agora(),
          'pacote_venda_sessao_id': item.sessaoId,
        });
        await txn.update(
          'pacote_venda_sessoes',
          {
            'profissional_id': item.profissionalId,
            'agendamento_id': agendamentoId,
            'inicio_planejado': item.inicio.toIso8601String(),
            'status': 'agendada',
            'atualizado_em': _agora(),
          },
          where: 'id=? AND comercio_id=? AND status=?',
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
        '''SELECT a.*, ps.id sessao_id, ps.pacote_venda_id, ps.status sessao_status,
           ps.credito_consumido, pv.valor_contratado, pv.total_sessoes,
           p.modo_comissao, s.comissao_percentual
           FROM agendamentos a
           JOIN pacote_venda_sessoes ps ON ps.id=a.pacote_venda_sessao_id
           JOIN pacote_vendas pv ON pv.id=ps.pacote_venda_id
           JOIN pacotes_servicos p ON p.id=pv.pacote_id
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
          'atualizado_em': agora,
        },
        where: 'id=? AND comercio_id=?',
        whereArgs: [agendamentoId, _comercioId],
      );
      await txn.update(
        'pacote_venda_sessoes',
        {
          'status': 'realizada',
          'credito_consumido': 1,
          'realizada_em': agora,
          'atualizado_em': agora,
        },
        where: 'id=? AND comercio_id=? AND credito_consumido=0',
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
      final modo = row['modo_comissao'] as String;
      if (modo == 'por_sessao' || modo == 'dividida') {
        await _comissao(
          txn,
          vendaId: row['pacote_venda_id'] as String,
          sessaoId: row['sessao_id'] as String,
          profissionalId: row['profissional_id'] as String,
          papel: 'executor',
          base:
              (row['valor_contratado'] as num).toDouble() /
              (row['total_sessoes'] as num).toInt(),
          percentual: (row['comissao_percentual'] as num? ?? 0).toDouble(),
        );
      }
      final restantes =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              '''SELECT COUNT(*) FROM pacote_venda_sessoes
               WHERE pacote_venda_id=? AND credito_consumido<1
               AND status NOT IN ('cancelada','vencida')''',
              [row['pacote_venda_id']],
            ),
          ) ??
          0;
      if (restantes == 0) {
        await txn.update(
          'pacote_vendas',
          {'status': 'concluido', 'atualizado_em': agora},
          where: 'id=? AND comercio_id=?',
          whereArgs: [row['pacote_venda_id'], _comercioId],
        );
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
        '''SELECT a.pacote_venda_sessao_id sessao_id, ps.pacote_venda_id,
           p.regra_falta, p.percentual_falta
           FROM agendamentos a JOIN pacote_venda_sessoes ps
           ON ps.id=a.pacote_venda_sessao_id JOIN pacote_vendas pv
           ON pv.id=ps.pacote_venda_id JOIN pacotes_servicos p ON p.id=pv.pacote_id
           WHERE a.id=? AND a.comercio_id=?''',
        [agendamentoId, _comercioId],
      );
      if (rows.isEmpty) throw StateError('Sessão de pacote não encontrada.');
      final row = rows.first;
      final regra = row['regra_falta'] as String;
      if (regra == 'aprovar' && !aprovada) {
        throw StateError('Esta falta exige aprovação administrativa.');
      }
      final consumo = regra == 'consumir'
          ? 1.0
          : regra == 'parcial'
          ? ((row['percentual_falta'] as num).toDouble() / 100).clamp(0, 1)
          : 0.0;
      await txn.update(
        'agendamentos',
        {'status': 'faltou', 'compareceu': 0, 'atualizado_em': _agora()},
        where: 'id=? AND comercio_id=?',
        whereArgs: [agendamentoId, _comercioId],
      );
      await txn.update(
        'pacote_venda_sessoes',
        {
          'status': consumo >= 1 ? 'faltou_consumida' : 'disponivel',
          'credito_consumido': consumo,
          'agendamento_id': consumo >= 1 ? agendamentoId : null,
          'falta_regra_aplicada': regra,
          'atualizado_em': _agora(),
        },
        where: 'id=? AND comercio_id=?',
        whereArgs: [row['sessao_id'], _comercioId],
      );
      await _auditar(
        txn,
        acao: 'falta_registrada',
        vendaId: row['pacote_venda_id'] as String,
        sessaoId: row['sessao_id'] as String,
        dados: {'regra': regra, 'credito_consumido': consumo},
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
        'pacote_venda_sessoes',
        where: 'id=? AND comercio_id=? AND status=?',
        whereArgs: [sessaoId, _comercioId, 'agendada'],
        limit: 1,
      );
      if (origemRows.isEmpty) {
        throw StateError('Sessão agendada não encontrada.');
      }
      final origem = origemRows.first;
      final inicioOriginal = DateTime.parse(
        origem['inicio_planejado'] as String,
      );
      final delta = novoInicio.difference(inicioOriginal);
      final selecionadas = await txn.query(
        'pacote_venda_sessoes',
        where: escopo == EscopoReagendamentoPacote.somenteEsta
            ? 'id=? AND comercio_id=?'
            : "pacote_venda_id=? AND comercio_id=? AND status='agendada' AND numero>=?",
        whereArgs: escopo == EscopoReagendamentoPacote.somenteEsta
            ? [sessaoId, _comercioId]
            : [origem['pacote_venda_id'], _comercioId, origem['numero']],
        orderBy: 'numero',
      );
      final idsAgendamento = selecionadas
          .map((r) => r['agendamento_id'] as String?)
          .whereType<String>()
          .toList();
      for (final sessao in selecionadas) {
        final atual = DateTime.parse(sessao['inicio_planejado'] as String);
        final inicio = atual.add(delta);
        final fim = inicio.add(
          Duration(minutes: sessao['duracao_minutos'] as int),
        );
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
          throw StateError('O reagendamento produziria conflito.');
        }
        await txn.update(
          'agendamentos',
          {
            'profissional_id': profissionalId,
            'inicio': inicio.toIso8601String(),
            'fim': fim.toIso8601String(),
            'status': 'agendado',
            'confirmado': 0,
            'atualizado_em': _agora(),
          },
          where: 'id=? AND comercio_id=?',
          whereArgs: [sessao['agendamento_id'], _comercioId],
        );
        await txn.update(
          'pacote_venda_sessoes',
          {
            'profissional_id': profissionalId,
            'inicio_planejado': inicio.toIso8601String(),
            'atualizado_em': _agora(),
          },
          where: 'id=? AND comercio_id=?',
          whereArgs: [sessao['id'], _comercioId],
        );
      }
      await _auditar(
        txn,
        acao: 'sessoes_reagendadas',
        vendaId: origem['pacote_venda_id'] as String,
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
        'agendamentos',
        columns: ['pacote_venda_sessao_id'],
        where: 'id=? AND comercio_id=?',
        whereArgs: [agendamentoId, _comercioId],
        limit: 1,
      );
      if (rows.isEmpty || rows.first['pacote_venda_sessao_id'] == null) return;
      await txn.update(
        'pacote_venda_sessoes',
        {
          'status': 'disponivel',
          'agendamento_id': null,
          'inicio_planejado': null,
          'profissional_id': null,
          'atualizado_em': _agora(),
        },
        where: 'id=? AND comercio_id=? AND credito_consumido=0',
        whereArgs: [rows.first['pacote_venda_sessao_id'], _comercioId],
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
      'pacote_vendas',
      {
        'status': status,
        'pausado_em': status == 'pausado' ? _agora() : null,
        'motivo_cancelamento': status == 'cancelado' ? motivo : null,
        'atualizado_em': _agora(),
      },
      where: 'id=? AND comercio_id=?',
      whereArgs: [vendaId, _comercioId],
    );
  }

  Future<void> estenderValidade(String vendaId, int dias) async {
    _exigir(AcaoPermissao.alterarValidadePacote);
    if (dias <= 0) throw ArgumentError('Informe dias adicionais.');
    final db = await _databaseProvider();
    final rows = await db.query(
      'pacote_vendas',
      columns: ['validade_em'],
      where: 'id=? AND comercio_id=?',
      whereArgs: [vendaId, _comercioId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Venda não encontrada.');
    final validade = DateTime.parse(
      rows.first['validade_em'] as String,
    ).add(Duration(days: dias));
    await db.update(
      'pacote_vendas',
      {'validade_em': validade.toIso8601String(), 'atualizado_em': _agora()},
      where: 'id=? AND comercio_id=?',
      whereArgs: [vendaId, _comercioId],
    );
  }

  Future<void> transferir(String vendaId, String novoClienteId) async {
    _exigir(AcaoPermissao.transferirPacote);
    final db = await _databaseProvider();
    await db.transaction((txn) async {
      final vendas = await txn.rawQuery(
        '''SELECT v.*, p.permite_transferencia FROM pacote_vendas v
           JOIN pacotes_servicos p ON p.id=v.pacote_id
           WHERE v.id=? AND v.comercio_id=?''',
        [vendaId, _comercioId],
      );
      if (vendas.isEmpty || vendas.first['permite_transferencia'] != 1) {
        throw StateError('Este pacote não permite transferência.');
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
        'pacote_vendas',
        {
          'cliente_origem_id': vendas.first['cliente_id'],
          'cliente_id': novoClienteId,
          'atualizado_em': _agora(),
        },
        where: 'id=? AND comercio_id=?',
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
      '''SELECT COUNT(*) quantidade, COALESCE(SUM(valor_contratado),0) vendido,
         COALESCE(SUM(valor_pago),0) recebido, COALESCE(SUM(valor_pendente),0) pendente
         FROM pacote_vendas WHERE comercio_id=? AND data_compra BETWEEN ? AND ?''',
      [_comercioId, de, ate],
    );
    final sessoes = await db.rawQuery(
      '''SELECT status, COUNT(*) quantidade FROM pacote_venda_sessoes
         WHERE comercio_id=? GROUP BY status''',
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
         JOIN pacote_vendas v ON v.id=a.pacote_venda_id
         JOIN pacotes_servicos p ON p.id=v.pacote_id
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
      'pacote_vendas',
      where: "comercio_id=? AND status IN ('ativo','pausado')",
      whereArgs: [_comercioId],
    );
    for (final venda in vendas) {
      final validade = DateTime.parse(venda['validade_em'] as String);
      final diferenca = validade.difference(agora).inDays;
      if (validade.isBefore(agora)) {
        await db.update(
          'pacote_vendas',
          {'status': 'vencido', 'atualizado_em': _agora()},
          where: 'id=? AND comercio_id=?',
          whereArgs: [venda['id'], _comercioId],
        );
        await db.update(
          'pacote_venda_sessoes',
          {'status': 'vencida', 'atualizado_em': _agora()},
          where: "pacote_venda_id=? AND comercio_id=? AND status='disponivel'",
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
      if ((venda['valor_pendente'] as num).toDouble() > 0) {
        alertas.add({
          'tipo': 'pagamento_pendente',
          'mensagem': 'Pacote com pagamento pendente.',
        });
      }
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

  String _regraFalta(RegraFaltaPacote regra) => regra.name;
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
