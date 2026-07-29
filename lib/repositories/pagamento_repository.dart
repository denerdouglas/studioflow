import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../models/domain/acesso.dart';
import '../models/domain/atendimento.dart';
import '../services/pix_payload_service.dart';
import '../services/session_controller.dart';

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
      if (item['agendamento_id'] != null) {
        await txn.update(
          'agendamentos',
          {'sinal_status': 'confirmado_manual'},
          where: 'id = ? AND comercio_id = ?',
          whereArgs: [item['agendamento_id'], _comercioId],
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
