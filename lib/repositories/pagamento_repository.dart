import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../models/domain/acesso.dart';
import '../models/domain/atendimento.dart';
import '../services/pix_payload_service.dart';
import '../services/session_controller.dart';
import 'recebimento_servico_writer.dart';

class PagamentoRepository {
  final Future<Database> Function() _databaseProvider;
  final String? _comercioInformado;
  final String? _usuarioInformado;
  final PixPayloadService _pix;

  PagamentoRepository({
    Future<Database> Function()? databaseProvider,
    String? comercioId,
    String? usuarioId,
    this._pix = const PixPayloadService(),
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseService.instance.database),
       _comercioInformado = comercioId,
       _usuarioInformado = usuarioId;

  String get _comercioId =>
      _comercioInformado ?? SessionController.instance.usuario!.comercioId;
  String get _usuarioId =>
      _usuarioInformado ?? SessionController.instance.usuario!.id;
  String _id(String prefixo) =>
      '${prefixo}_${_comercioId}_${DateTime.now().microsecondsSinceEpoch}';

  void _exigir(AcaoPermissao acao) {
    final usuario = SessionController.instance.usuario;
    if (usuario == null || !usuario.podeAcao(acao)) {
      throw StateError(
        'Você não possui permissão para ${acao.nome.toLowerCase()}.',
      );
    }
  }

  Future<ConfiguracaoPagamento> carregarConfiguracao() async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'configuracoes_pagamento',
      where: 'comercio_id = ?',
      whereArgs: [_comercioId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return ConfiguracaoPagamento(
        comercioId: _comercioId,
        chavePix: '',
        tipoChave: 'aleatoria',
        nomeRecebedor: '',
        cidadeRecebedor: '',
        mensagemCobranca: 'Segue a cobrança do seu atendimento.',
        tipoSinal: 'percentual',
        valorSinal: 0,
        prazoHoras: 24,
        politicaCancelamento: '',
      );
    }
    final e = rows.first;
    return ConfiguracaoPagamento(
      comercioId: _comercioId,
      chavePix: e['chave_pix'] as String? ?? '',
      tipoChave: e['tipo_chave'] as String? ?? 'aleatoria',
      nomeRecebedor: e['nome_recebedor'] as String? ?? '',
      cidadeRecebedor: e['cidade_recebedor'] as String? ?? '',
      mensagemCobranca: e['mensagem_cobranca'] as String? ?? '',
      tipoSinal: e['tipo_sinal'] as String? ?? 'percentual',
      valorSinal: (e['valor_sinal'] as num? ?? 0).toDouble(),
      prazoHoras: (e['prazo_horas'] as num? ?? 24).toInt(),
      politicaCancelamento: e['politica_cancelamento'] as String? ?? '',
      linkPagamentoBase: e['link_pagamento_base'] as String? ?? '',
      banco: e['banco'] as String? ?? '',
      observacoes: e['observacoes'] as String? ?? '',
      formasAceitas: _formasAceitas(e['formas_aceitas'] as String?),
      valorSinalFixo: (e['valor_sinal_fixo'] as num? ?? 0).toDouble(),
      percentualSinal: (e['percentual_sinal'] as num? ?? 0).toDouble(),
    );
  }

  Future<void> salvarConfiguracao(ConfiguracaoPagamento config) async {
    _exigir(AcaoPermissao.configurarPix);
    final db = await _databaseProvider();
    await db.insert('configuracoes_pagamento', {
      'comercio_id': _comercioId,
      'chave_pix': config.chavePix.trim(),
      'tipo_chave': config.tipoChave,
      'nome_recebedor': config.nomeRecebedor.trim(),
      'cidade_recebedor': config.cidadeRecebedor.trim(),
      'mensagem_cobranca': config.mensagemCobranca.trim(),
      'tipo_sinal': config.tipoSinal,
      'valor_sinal': config.valorSinal,
      'prazo_horas': config.prazoHoras,
      'politica_cancelamento': config.politicaCancelamento.trim(),
      'link_pagamento_base': config.linkPagamentoBase.trim(),
      'banco': config.banco.trim(),
      'observacoes': config.observacoes.trim(),
      'formas_aceitas': config.formasAceitas.join(','),
      'valor_sinal_fixo': config.valorSinalFixo,
      'percentual_sinal': config.percentualSinal,
      'atualizado_em': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Cobranca> criarCobranca({
    String? agendamentoId,
    String? clienteId,
    required double valor,
    required String descricao,
    String forma = 'pix',
  }) async {
    _exigir(AcaoPermissao.acessarFinanceiro);
    if (valor <= 0) throw ArgumentError('Informe um valor válido.');
    final db = await _databaseProvider();
    final config = await carregarConfiguracao();
    final id = _id('cob');
    var copiaCola = '';
    var link = '';
    if (forma == 'pix') {
      copiaCola = _pix.gerar(
        chave: config.chavePix,
        nomeRecebedor: config.nomeRecebedor,
        cidade: config.cidadeRecebedor,
        valor: valor,
        referencia: id,
      );
    } else if (forma == 'link') {
      if (config.linkPagamentoBase.isEmpty) {
        throw StateError(
          'Configure um link de pagamento fornecido pelo seu provedor.',
        );
      }
      link = config.linkPagamentoBase;
    }
    final agora = DateTime.now().toUtc();
    await db.transaction((txn) async {
      await txn.insert('cobrancas', {
        'id': id,
        'comercio_id': _comercioId,
        'agendamento_id': agendamentoId,
        'cliente_id': clienteId,
        'valor': valor,
        'descricao': descricao.trim(),
        'forma': forma,
        'pix_copia_cola': copiaCola,
        'link_pagamento': link,
        'status': 'pendente',
        'criado_em': agora.toIso8601String(),
      });
      if (agendamentoId != null) {
        await txn.update(
          'agendamentos',
          {'sinal_valor': valor, 'sinal_status': 'pendente'},
          where: 'id = ? AND comercio_id = ?',
          whereArgs: [agendamentoId, _comercioId],
        );
      }
    });
    return Cobranca(
      id: id,
      agendamentoId: agendamentoId,
      clienteId: clienteId,
      valor: valor,
      descricao: descricao,
      forma: forma,
      pixCopiaCola: copiaCola,
      linkPagamento: link,
      status: 'pendente',
      criadaEm: agora,
    );
  }

  String textoCobranca(Cobranca cobranca, ConfiguracaoPagamento config) {
    final destino = cobranca.forma == 'pix'
        ? 'Pix Copia e Cola:\n${cobranca.pixCopiaCola}'
        : 'Link de pagamento:\n${cobranca.linkPagamento}';
    return '${config.mensagemCobranca}\n\n${cobranca.descricao}\n'
        'Valor: R\$ ${cobranca.valor.toStringAsFixed(2)}\n\n$destino\n\n'
        'O pagamento será confirmado após validação manual ou retorno do provedor.';
  }

  Future<List<Cobranca>> listarCobrancas() async {
    _exigir(AcaoPermissao.acessarFinanceiro);
    final db = await _databaseProvider();
    final rows = await db.query(
      'cobrancas',
      where: 'comercio_id = ?',
      whereArgs: [_comercioId],
      orderBy: 'criado_em DESC',
    );
    return rows.map(_doMapa).toList();
  }

  Future<void> confirmarManual(String cobrancaId) async {
    _exigir(AcaoPermissao.acessarFinanceiro);
    final db = await _databaseProvider();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'cobrancas',
        where: 'id = ? AND comercio_id = ?',
        whereArgs: [cobrancaId, _comercioId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Cobrança não encontrada.');
      final item = rows.first;
      final agora = DateTime.now().toUtc().toIso8601String();
      final agendamentoId = item['agendamento_id'] as String?;
      if (agendamentoId != null) {
        await RecebimentoServicoWriter.registrar(
          txn,
          comercioId: _comercioId,
          agendamentoId: agendamentoId,
          valor: (item['valor'] as num).toDouble(),
          formaPagamento: item['forma'] as String,
          referencia: cobrancaId,
          entidadeOrigem: 'cobranca',
          usuarioId: _usuarioId,
        );
      } else {
        final existente = await txn.query(
          'movimentacoes_financeiras',
          columns: ['id'],
          where: 'comercio_id=? AND entidade_origem=? AND entidade_origem_id=?',
          whereArgs: [_comercioId, 'cobranca', cobrancaId],
          limit: 1,
        );
        if (existente.isEmpty) {
          await txn.insert('movimentacoes_financeiras', {
            'id': 'recebimento_$cobrancaId',
            'comercio_id': _comercioId,
            'tipo': 'entrada',
            'descricao': item['descricao'],
            'valor': item['valor'],
            'forma_pagamento': item['forma'],
            'status': 'pago',
            'data': agora,
            'data_criacao': agora,
            'categoria': 'Cobranças',
            'cliente_id': item['cliente_id'],
            'usuario_responsavel_id': _usuarioId,
            'observacoes': 'pagamento_confirmado',
            'entidade_origem': 'cobranca',
            'entidade_origem_id': cobrancaId,
          });
        }
      }
      await txn.update(
        'cobrancas',
        {
          'status': 'confirmado_manual',
          'origem_confirmacao': 'usuario_autorizado',
          'confirmado_por_id': _usuarioId,
          'confirmado_em': agora,
        },
        where: 'id = ? AND comercio_id = ?',
        whereArgs: [cobrancaId, _comercioId],
      );
      if (agendamentoId != null) {
        await txn.update(
          'agendamentos',
          {'sinal_status': 'confirmado_manual'},
          where: 'id = ? AND comercio_id = ?',
          whereArgs: [agendamentoId, _comercioId],
        );
      }
    });
  }

  Future<bool> registrarPagamentoAtendimento({
    required String agendamentoId,
    required double valor,
    required String formaPagamento,
    required String referencia,
  }) async {
    _exigir(AcaoPermissao.acessarFinanceiro);
    final db = await _databaseProvider();
    return db.transaction(
      (txn) => RecebimentoServicoWriter.registrar(
        txn,
        comercioId: _comercioId,
        agendamentoId: agendamentoId,
        valor: valor,
        formaPagamento: formaPagamento,
        referencia: referencia,
        entidadeOrigem: 'pagamento_atendimento',
        usuarioId: _usuarioId,
      ),
    );
  }

  Future<void> estornarRecebimentoAtendimento({
    required String movimentoId,
    required String motivo,
  }) async {
    _exigir(AcaoPermissao.acessarFinanceiro);
    if (motivo.trim().length < 3) {
      throw StateError('Informe o motivo do estorno.');
    }
    final db = await _databaseProvider();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'movimentacoes_financeiras',
        where:
            "id=? AND comercio_id=? AND tipo='entrada' AND status='pago' AND centro_resultado='salao'",
        whereArgs: [movimentoId, _comercioId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Recebimento não encontrado ou já estornado.');
      }
      final movimento = rows.single;
      final agendaId = movimento['agendamento_id'] as String?;
      if (agendaId == null) throw StateError('Recebimento sem atendimento.');
      final agora = DateTime.now().toUtc().toIso8601String();
      await txn.update(
        'movimentacoes_financeiras',
        {'status': 'estornado'},
        where: 'id=? AND comercio_id=?',
        whereArgs: [movimentoId, _comercioId],
      );
      await txn.insert('movimentacoes_financeiras', {
        ...movimento,
        'id': '${movimentoId}_estorno',
        'tipo': 'saida',
        'valor': (movimento['valor'] as num).toDouble().abs(),
        'status': 'pago',
        'descricao': 'Estorno - ${movimento['descricao']}',
        'data': agora,
        'data_criacao': agora,
        'observacoes': motivo.trim(),
        'entidade_origem': 'estorno_recebimento',
        'entidade_origem_id': movimentoId,
      });
      final agendas = await txn.query(
        'agendamentos',
        columns: ['valor_recebido', 'valor_servico', 'desconto'],
        where: 'id=? AND comercio_id=?',
        whereArgs: [agendaId, _comercioId],
        limit: 1,
      );
      if (agendas.isNotEmpty) {
        final agenda = agendas.single;
        final recebido = (agenda['valor_recebido'] as num).toDouble();
        final novo = (recebido - (movimento['valor'] as num).toDouble()).clamp(
          0,
          double.infinity,
        );
        await txn.update(
          'agendamentos',
          {
            'valor_recebido': novo,
            'pagamento_status': novo <= 0.005 ? 'pendente' : 'parcial',
            'atualizado_em': agora,
          },
          where: 'id=? AND comercio_id=?',
          whereArgs: [agendaId, _comercioId],
        );
      }
      if (movimento['entidade_origem'] == 'cobranca') {
        await txn.update(
          'cobrancas',
          {'status': 'estornada'},
          where: 'id=? AND comercio_id=?',
          whereArgs: [movimento['entidade_origem_id'], _comercioId],
        );
        await txn.update(
          'agendamentos',
          {'sinal_status': 'estornado'},
          where: 'id=? AND comercio_id=?',
          whereArgs: [agendaId, _comercioId],
        );
      }
    });
  }

  static Set<String> _formasAceitas(String? valor) {
    if (valor == null || valor.trim().isEmpty) return {'pix', 'dinheiro'};
    final normalizado = valor
        .replaceAll('[', '')
        .replaceAll(']', '')
        .replaceAll('"', '');
    return normalizado
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
  }

  static Cobranca _doMapa(Map<String, Object?> e) => Cobranca(
    id: e['id'] as String,
    agendamentoId: e['agendamento_id'] as String?,
    clienteId: e['cliente_id'] as String?,
    valor: (e['valor'] as num).toDouble(),
    descricao: e['descricao'] as String,
    forma: e['forma'] as String,
    pixCopiaCola: e['pix_copia_cola'] as String? ?? '',
    linkPagamento: e['link_pagamento'] as String? ?? '',
    status: e['status'] as String,
    criadaEm: DateTime.parse(e['criado_em'] as String),
    confirmadaEm: DateTime.tryParse(e['confirmado_em'] as String? ?? ''),
  );
}
