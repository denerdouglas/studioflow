import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../integrations/atendimento_providers.dart';
import '../models/domain/acesso.dart';
import '../models/domain/atendimento.dart';
import '../services/session_controller.dart';
import 'agenda_completa_repository.dart';

class AtendimentoIaRepository implements AIProvider {
  final Future<Database> Function() _databaseProvider;
  final String? _comercioInformado;

  AtendimentoIaRepository({
    Future<Database> Function()? databaseProvider,
    String? comercioId,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseService.instance.database),
       _comercioInformado = comercioId;

  String get _comercioId =>
      _comercioInformado ?? SessionController.instance.usuario!.comercioId;
  String _id(String prefixo) =>
      '${prefixo}_${_comercioId}_${IdGenerator.temporal()}';

  void _exigir(AcaoPermissao acao) {
    final usuario = SessionController.instance.usuario;
    if (usuario == null || !usuario.podeAcao(acao)) {
      throw StateError(
        'Você não possui permissão para ${acao.nome.toLowerCase()}.',
      );
    }
  }

  @override
  bool get online => false;

  Future<ConfiguracaoIaSalao> carregarConfiguracao() async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'configuracoes_ia',
      where: 'comercio_id = ?',
      whereArgs: [_comercioId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return ConfiguracaoIaSalao(
        comercioId: _comercioId,
        nomeIa: 'Sofia',
        mensagemApresentacao: 'Olá! Como posso ajudar?',
        estiloLinguagem: 'descontraido',
        horarioInicio: '08:00',
        horarioFim: '18:00',
        politicaCancelamento: '',
        instrucaoTransferencia: 'Vou transferir para uma pessoa da equipe.',
        transferirPalavras: 'humano,atendente,pessoa',
      );
    }
    final e = rows.first;
    return ConfiguracaoIaSalao(
      comercioId: _comercioId,
      nomeIa: e['nome_ia'] as String,
      mensagemApresentacao: e['mensagem_apresentacao'] as String,
      estiloLinguagem: e['estilo_linguagem'] as String,
      horarioInicio: e['horario_inicio'] as String,
      horarioFim: e['horario_fim'] as String,
      politicaCancelamento: e['politica_cancelamento'] as String,
      instrucaoTransferencia: e['instrucao_transferencia'] as String,
      transferirPalavras: e['transferir_palavras'] as String,
      ativo: (e['ativo'] as int) == 1,
    );
  }

  Future<void> salvarConfiguracao(ConfiguracaoIaSalao config) async {
    _exigir(AcaoPermissao.configurarIa);
    final db = await _databaseProvider();
    await db.insert('configuracoes_ia', {
      'comercio_id': _comercioId,
      'nome_ia': config.nomeIa.trim(),
      'mensagem_apresentacao': config.mensagemApresentacao.trim(),
      'estilo_linguagem': config.estiloLinguagem,
      'horario_inicio': config.horarioInicio,
      'horario_fim': config.horarioFim,
      'politica_cancelamento': config.politicaCancelamento.trim(),
      'instrucao_transferencia': config.instrucaoTransferencia.trim(),
      'transferir_palavras': config.transferirPalavras.trim(),
      'ativo': config.ativo ? 1 : 0,
      'atualizado_em': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<FaqIa>> listarFaqs() async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'faq_ia',
      where: 'comercio_id = ? AND ativo = 1',
      whereArgs: [_comercioId],
      orderBy: 'pergunta COLLATE NOCASE',
    );
    return rows
        .map(
          (e) => FaqIa(
            id: e['id'] as String,
            pergunta: e['pergunta'] as String,
            resposta: e['resposta'] as String,
            ativo: (e['ativo'] as int) == 1,
          ),
        )
        .toList();
  }

  Future<void> salvarFaq(FaqIa faq) async {
    _exigir(AcaoPermissao.configurarIa);
    if (faq.pergunta.trim().isEmpty || faq.resposta.trim().isEmpty) {
      throw ArgumentError('Informe pergunta e resposta.');
    }
    final db = await _databaseProvider();
    final agora = DateTime.now().toUtc().toIso8601String();
    await db.insert('faq_ia', {
      'id': faq.id.isEmpty ? _id('faq') : faq.id,
      'comercio_id': _comercioId,
      'pergunta': faq.pergunta.trim(),
      'resposta': faq.resposta.trim(),
      'ativo': faq.ativo ? 1 : 0,
      'criado_em': agora,
      'atualizado_em': agora,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removerFaq(String id) async {
    _exigir(AcaoPermissao.configurarIa);
    final db = await _databaseProvider();
    await db.update(
      'faq_ia',
      {'ativo': 0, 'atualizado_em': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [id, _comercioId],
    );
  }

  Future<String> iniciarConversa() async {
    _exigir(AcaoPermissao.visualizarConversas);
    final db = await _databaseProvider();
    final id = _id('conv');
    await db.insert('conversas_simuladas', {
      'id': id,
      'comercio_id': _comercioId,
      'canal': 'simulador',
      'status': 'aberta',
      'iniciada_em': DateTime.now().toUtc().toIso8601String(),
    });
    final config = await carregarConfiguracao();
    await _registrar(id, 'assistente', config.mensagemApresentacao);
    return id;
  }

  Future<List<MensagemSimulada>> listarMensagens(String conversaId) async {
    _exigir(AcaoPermissao.visualizarConversas);
    final db = await _databaseProvider();
    final rows = await db.query(
      'mensagens_simuladas',
      where: 'comercio_id = ? AND conversa_id = ?',
      whereArgs: [_comercioId, conversaId],
      orderBy: 'criada_em',
    );
    return rows
        .map(
          (e) => MensagemSimulada(
            id: e['id'] as String,
            remetente: e['remetente'] as String,
            conteudo: e['conteudo'] as String,
            criadaEm: DateTime.parse(e['criada_em'] as String),
          ),
        )
        .toList();
  }

  @override
  Future<String> responder({
    required String comercioId,
    required String conversaId,
    required String mensagem,
  }) async {
    _exigir(AcaoPermissao.visualizarConversas);
    if (comercioId != _comercioId) {
      throw StateError('Conversa não pertence ao comércio atual.');
    }
    await _registrar(conversaId, 'cliente', mensagem);
    final resposta = await _respostaLocal(mensagem);
    await _registrar(conversaId, 'assistente', resposta);
    return resposta;
  }

  Future<String> _respostaLocal(String mensagem) async {
    final db = await _databaseProvider();
    final config = await carregarConfiguracao();
    final texto = _normalizar(mensagem);
    final palavrasHumano = config.transferirPalavras
        .split(',')
        .map(_normalizar)
        .where((item) => item.isNotEmpty);
    if (palavrasHumano.any(texto.contains)) {
      return config.instrucaoTransferencia.isEmpty
          ? 'Vou encaminhar sua conversa para uma pessoa da equipe.'
          : config.instrucaoTransferencia;
    }
    final faqs = await listarFaqs();
    for (final faq in faqs) {
      final termos = _normalizar(
        faq.pergunta,
      ).split(' ').where((item) => item.length > 3);
      if (termos.any(texto.contains)) return faq.resposta;
    }
    if (texto.contains('servico') || texto.contains('preco')) {
      final rows = await db.query(
        'servicos',
        columns: ['nome', 'preco', 'duracao_minutos'],
        where: 'comercio_id = ? AND ativo = 1',
        whereArgs: [_comercioId],
        orderBy: 'nome COLLATE NOCASE',
        limit: 8,
      );
      if (rows.isEmpty) return 'Ainda não há serviços cadastrados.';
      return rows
          .map(
            (e) =>
                '${e['nome']}: R\$ ${(e['preco'] as num).toStringAsFixed(2)} '
                '(${e['duracao_minutos']} min)',
          )
          .join('\n');
    }
    if (texto.contains('profissional')) {
      final rows = await db.query(
        'profissionais',
        columns: ['nome', 'cargo'],
        where: 'comercio_id = ? AND ativo = 1',
        whereArgs: [_comercioId],
        orderBy: 'nome COLLATE NOCASE',
      );
      return rows.isEmpty
          ? 'Ainda não há profissionais cadastrados.'
          : 'Nossa equipe:\n${rows.map((e) => '${e['nome']} — ${e['cargo']}').join('\n')}';
    }
    if (texto.contains('horario') || texto.contains('agendar')) {
      final profissionais = await db.query(
        'profissionais',
        columns: ['id', 'nome'],
        where: 'comercio_id = ? AND ativo = 1',
        whereArgs: [_comercioId],
        limit: 1,
      );
      if (profissionais.isEmpty) {
        return 'Cadastre um profissional para consultar horários.';
      }
      final amanha = DateTime.now().add(const Duration(days: 1));
      final livres =
          await AgendaCompletaRepository(
            databaseProvider: _databaseProvider,
            comercioId: _comercioId,
            usuarioId: 'simulador',
          ).horariosDisponiveis(
            profissionalId: profissionais.first['id'] as String,
            data: amanha,
            duracaoMinutos: 60,
          );
      if (livres.isEmpty) {
        return 'Não encontrei horários livres amanhã. Confira a jornada do profissional na Agenda.';
      }
      final horarios = livres
          .take(5)
          .map(
            (e) =>
                '${e.hour.toString().padLeft(2, '0')}:${e.minute.toString().padLeft(2, '0')}',
          )
          .join(', ');
      return 'Amanhã, ${profissionais.first['nome']} tem estes horários: $horarios.';
    }
    if (texto.contains('pix') || texto.contains('pagamento')) {
      final rows = await db.query(
        'configuracoes_pagamento',
        columns: ['chave_pix', 'mensagem_cobranca'],
        where: 'comercio_id = ?',
        whereArgs: [_comercioId],
        limit: 1,
      );
      if (rows.isEmpty || (rows.first['chave_pix'] as String? ?? '').isEmpty) {
        return 'O Pix ainda não foi configurado. Vou transferir para a equipe.';
      }
      return '${rows.first['mensagem_cobranca']}\nChave Pix: ${rows.first['chave_pix']}\n'
          'A confirmação depende da equipe ou do provedor de pagamento.';
    }
    if (texto.contains('cancel') || texto.contains('reagend')) {
      return config.politicaCancelamento.isEmpty
          ? 'Para cancelar ou reagendar, informe seu nome, data e horário. A equipe confirmará a alteração.'
          : config.politicaCancelamento;
    }
    return 'Posso ajudar com agendamento, serviços, preços, profissionais, Pix, reagendamento ou atendimento humano.';
  }

  Future<void> _registrar(
    String conversaId,
    String remetente,
    String conteudo,
  ) async {
    final db = await _databaseProvider();
    final conversa = await db.query(
      'conversas_simuladas',
      columns: ['id'],
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [conversaId, _comercioId],
      limit: 1,
    );
    if (conversa.isEmpty) throw StateError('Conversa não encontrada.');
    await db.insert('mensagens_simuladas', {
      'id': _id('msg'),
      'conversa_id': conversaId,
      'comercio_id': _comercioId,
      'remetente': remetente,
      'conteudo': conteudo.trim(),
      'criada_em': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static String _normalizar(String valor) => valor
      .toLowerCase()
      .replaceAll(RegExp('[áàãâä]'), 'a')
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[íìîï]'), 'i')
      .replaceAll(RegExp('[óòõôö]'), 'o')
      .replaceAll(RegExp('[úùûü]'), 'u')
      .replaceAll('ç', 'c');
}
