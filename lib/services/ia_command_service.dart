import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../models/domain/acesso.dart';
import 'session_controller.dart';
import 'whatsapp_queue_service.dart';

enum IaCommandKind { consulta, acao }

class IaCommandPreview {
  final String id;
  final IaCommandKind kind;
  final String intent;
  final String module;
  final String title;
  final Map<String, Object?> fields;
  final List<String> missingFields;
  final bool requiresConfirmation;

  const IaCommandPreview({
    required this.id,
    required this.kind,
    required this.intent,
    required this.module,
    required this.title,
    required this.fields,
    this.missingFields = const [],
    this.requiresConfirmation = true,
  });

  bool get ready => missingFields.isEmpty;
  String get summary {
    final values = fields.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    final missing = missingFields.isEmpty
        ? ''
        : '\nFaltando: ${missingFields.join(', ')}';
    return '$title\n\n$values$missing';
  }
}

class IaCommandResult {
  final String commandId;
  final String recordId;
  final String message;
  final int sent;
  final int pending;
  final int failures;
  final int ignored;
  const IaCommandResult({
    required this.commandId,
    required this.recordId,
    required this.message,
    this.sent = 0,
    this.pending = 0,
    this.failures = 0,
    this.ignored = 0,
  });
}

class IaCommandService {
  final Future<Database> Function() _databaseProvider;
  final WhatsappQueueService _whatsapp;
  IaCommandService({
    Future<Database> Function()? databaseProvider,
    WhatsappQueueService? whatsapp,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseService.instance.database),
       _whatsapp =
           whatsapp ?? WhatsappQueueService(databaseProvider: databaseProvider);

  Future<IaCommandPreview?> prepare(
    String input, {
    String? unitId,
    DateTime? now,
  }) async {
    final text = input.trim();
    final normalized = _normalize(text);
    if (text.isEmpty) {
      return null;
    }
    if (_isReminderAction(normalized)) {
      return _prepareReminders(unitId: unitId, now: now);
    }
    if (_isStockCreate(normalized)) {
      return _prepareStock(text, normalized, unitId);
    }
    if (_isStockAdd(normalized)) {
      return _prepareStockAddition(text, normalized, unitId);
    }
    if (_isServiceCreate(normalized)) {
      return _prepareService(text, normalized);
    }
    if (_isProfessionalCreate(normalized)) {
      return _prepareProfessional(text, normalized);
    }
    if (_isFinanceCreate(normalized)) {
      return _prepareExpense(text, normalized, unitId);
    }
    return null;
  }

  Future<IaCommandResult> execute(IaCommandPreview preview) async {
    if (preview.kind != IaCommandKind.acao || !preview.ready) {
      throw StateError(
        preview.missingFields.isEmpty
            ? 'Este pedido é uma consulta, não uma ação.'
            : 'Complete antes: ${preview.missingFields.join(', ')}.',
      );
    }
    final user = SessionController.instance.usuario;
    if (user == null) {
      throw StateError('Sessão não autenticada.');
    }
    _authorize(user, preview.module);
    final db = await _databaseProvider();
    final existing = await db.query(
      'ia_comandos',
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [preview.id, user.comercioId],
      limit: 1,
    );
    if (existing.isNotEmpty && existing.single['status'] == 'executado') {
      final result =
          jsonDecode(existing.single['resultado_json'] as String)
              as Map<String, dynamic>;
      return IaCommandResult(
        commandId: preview.id,
        recordId: result['recordId'] as String? ?? '',
        message: 'Ação já executada; nenhum registro foi duplicado.',
        sent: result['sent'] as int? ?? 0,
        pending: result['pending'] as int? ?? 0,
        failures: result['failures'] as int? ?? 0,
        ignored: result['ignored'] as int? ?? 0,
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('ia_comandos', {
      'id': preview.id,
      'comercio_id': user.comercioId,
      'unidade_id': preview.fields['unidade_id'],
      'usuario_id': user.id,
      'intencao': preview.intent,
      'modulo': preview.module,
      'payload_json': jsonEncode(preview.fields),
      'idempotency_key': preview.id,
      'status': 'confirmado',
      'criado_em': now,
      'confirmado_em': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    try {
      final result = await db.transaction((tx) async {
        return switch (preview.intent) {
          'enviar_lembretes_hoje' => _executeReminders(tx, user, preview),
          'criar_produto_estoque' => _executeStock(tx, user, preview),
          'adicionar_quantidade_estoque' => _executeStockAddition(
            tx,
            user,
            preview,
          ),
          'criar_servico' => _executeService(tx, user, preview),
          'criar_colaborador' => _executeProfessional(tx, user, preview),
          'criar_saida_caixa' => _executeExpense(tx, user, preview),
          _ => throw StateError('Comando ainda não possui executor real.'),
        };
      });
      final encoded = jsonEncode({
        'recordId': result.recordId,
        'sent': result.sent,
        'pending': result.pending,
        'failures': result.failures,
        'ignored': result.ignored,
      });
      await db.update(
        'ia_comandos',
        {
          'status': 'executado',
          'resultado_json': encoded,
          'executado_em': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [preview.id],
      );
      await _audit(db, user, preview, 'execucao', 'sucesso');
      return result;
    } catch (error) {
      await db.update(
        'ia_comandos',
        {'status': 'falhou', 'erro': '$error'},
        where: 'id = ?',
        whereArgs: [preview.id],
      );
      await _audit(db, user, preview, 'execucao', 'falha: $error');
      rethrow;
    }
  }

  Future<IaCommandPreview> _prepareReminders({
    String? unitId,
    DateTime? now,
  }) async {
    final user = _user();
    _authorize(user, 'agenda');
    final db = await _databaseProvider();
    final local = now ?? DateTime.now();
    final start = DateTime(local.year, local.month, local.day);
    final end = start.add(const Duration(days: 1));
    final rows = await db.rawQuery(
      '''SELECT a.id, c.nome, c.whatsapp,
      c.consentimento_whatsapp, a.inicio, s.nome servico, p.nome profissional
      FROM agendamentos a JOIN clientes c ON c.id=a.cliente_id
      JOIN servicos s ON s.id=a.servico_id JOIN profissionais p ON p.id=a.profissional_id
      WHERE a.comercio_id=? AND a.inicio>=? AND a.inicio<?
      AND a.status!='cancelado' AND a.excluido=0
      ${unitId == null ? '' : 'AND (a.unidade_id=? OR a.unidade_id IS NULL)'}''',
      [
        user.comercioId,
        start.toIso8601String(),
        end.toIso8601String(),
        ?unitId,
      ],
    );
    final valid = rows
        .where(
          (r) =>
              _validPhone(r['whatsapp'] as String?) &&
              r['consentimento_whatsapp'] == 1,
        )
        .length;
    return IaCommandPreview(
      id: _idempotency(user.comercioId, 'lembretes', start.toIso8601String()),
      kind: IaCommandKind.acao,
      intent: 'enviar_lembretes_hoje',
      module: 'agenda',
      title: 'Prévia — lembretes dos agendamentos de hoje',
      fields: {
        'unidade_id': unitId,
        'data': start.toIso8601String(),
        'agendamentos': rows.length,
        'destinatarios_validos': valid,
        'sem_contato_ou_consentimento': rows.length - valid,
        'modelo':
            'Olá, [cliente]! Lembrete: seu atendimento é hoje às [hora], com [profissional]. Serviço: [serviço].',
      },
    );
  }

  IaCommandPreview _prepareStock(String original, String text, String? unitId) {
    final quantity = _number(
      text,
      RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:unidades?|un\b)'),
    );
    final code = RegExp(r'codigo\s*(\d{4,})').firstMatch(text)?.group(1);
    final expiry = _date(text);
    final cost = _money(text, 'custo');
    final price = _money(text, 'preco de venda|preco');
    final name = _between(
      text,
      RegExp(r'cadastre\s+'),
      RegExp(r'\s+(?:marca|cor|\d+\s*unidade|custo|preco|vencimento|codigo)'),
    );
    final brand = _afterWord(text, 'marca');
    final color = _afterWord(text, 'cor');
    final missing = <String>[
      if (name == null) 'produto',
      if (quantity == null) 'quantidade',
    ];
    return _preview(
      'criar_produto_estoque',
      'estoque',
      'Novo item de estoque',
      {
        'unidade_id': unitId,
        'produto': name,
        'marca': brand,
        'cor': color,
        'quantidade': quantity,
        'data_validade': expiry?.toIso8601String(),
        'codigo_barras': code,
        'custo': cost,
        'preco_venda': price,
        'texto_original': original,
      },
      missing,
    );
  }

  IaCommandPreview _prepareStockAddition(
    String original,
    String text,
    String? unitId,
  ) {
    final quantity = _number(
      text,
      RegExp(r'(?:acrescente|adicione)\s+(\d+(?:[.,]\d+)?)'),
    );
    final name = RegExp(
      r'(?:ao|a)\s+(.+?)(?:\.|$)',
    ).firstMatch(text)?.group(1)?.trim();
    return _preview(
      'adicionar_quantidade_estoque',
      'estoque',
      'Atualizar quantidade do estoque',
      {
        'unidade_id': unitId,
        'produto': name,
        'quantidade': quantity,
        'texto_original': original,
      },
      [if (name == null) 'produto', if (quantity == null) 'quantidade'],
    );
  }

  IaCommandPreview _prepareService(String original, String text) {
    final duration = _number(text, RegExp(r'duracao\s+de\s+(\d+)'))?.round();
    final price = _money(text, 'valor|preco');
    final name = _between(
      text,
      RegExp(r'crie (?:um )?servico de\s+'),
      RegExp(r',|\s+duracao'),
    );
    final professional = RegExp(
      r'(?:feito|realizado) pela?\s+([a-z ]+?)(?:\.|$)',
    ).firstMatch(text)?.group(1)?.trim();
    return _preview(
      'criar_servico',
      'servicos',
      'Novo serviço',
      {
        'nome': name,
        'duracao_minutos': duration,
        'preco': price,
        'profissional': professional,
        'texto_original': original,
      },
      [
        if (name == null) 'nome',
        if (duration == null) 'duração',
        if (price == null) 'preço',
      ],
    );
  }

  IaCommandPreview _prepareProfessional(String original, String text) {
    final match = RegExp(
      r'cadastre (?:a|o)\s+([a-z ]+?)\s+como\s+(.+?)(?:\.|$)',
    ).firstMatch(text);
    final roles = match
        ?.group(2)
        ?.split(RegExp(r'\s+e\s+|,'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    return _preview(
      'criar_colaborador',
      'funcionarios',
      'Novo colaborador',
      {
        'nome': match?.group(1)?.trim(),
        'funcoes': roles,
        'texto_original': original,
      },
      [
        if (match?.group(1) == null) 'nome',
        if (roles == null || roles.isEmpty) 'funções',
      ],
    );
  }

  IaCommandPreview _prepareExpense(
    String original,
    String text,
    String? unitId,
  ) {
    final value = _money(text, 'caixa de|saida de|valor de');
    final description = RegExp(
      r'referente (?:a|à)\s+(.+?)(?:\.|$)',
    ).firstMatch(text)?.group(1)?.trim();
    return _preview(
      'criar_saida_caixa',
      'financeiro',
      'Nova saída de caixa',
      {
        'unidade_id': unitId,
        'valor': value,
        'descricao': description,
        'texto_original': original,
      },
      [if (value == null) 'valor', if (description == null) 'descrição'],
    );
  }

  IaCommandPreview _preview(
    String intent,
    String module,
    String title,
    Map<String, Object?> fields,
    List<String> missing,
  ) {
    final user = _user();
    return IaCommandPreview(
      id: _idempotency(user.comercioId, intent, jsonEncode(fields)),
      kind: IaCommandKind.acao,
      intent: intent,
      module: module,
      title: title,
      fields: fields,
      missingFields: missing,
    );
  }

  Future<IaCommandResult> _executeReminders(
    DatabaseExecutor tx,
    UsuarioAcesso user,
    IaCommandPreview preview,
  ) async {
    final start = DateTime.parse(preview.fields['data'] as String);
    final end = start.add(const Duration(days: 1));
    final rows = await tx.rawQuery(
      '''SELECT a.id,c.nome,c.whatsapp,c.consentimento_whatsapp,
      a.inicio,s.nome servico,p.nome profissional FROM agendamentos a
      JOIN clientes c ON c.id=a.cliente_id JOIN servicos s ON s.id=a.servico_id
      JOIN profissionais p ON p.id=a.profissional_id WHERE a.comercio_id=?
      AND a.inicio>=? AND a.inicio<? AND a.status!='cancelado' AND a.excluido=0''',
      [user.comercioId, start.toIso8601String(), end.toIso8601String()],
    );
    var pending = 0, ignored = 0, failures = 0;
    for (final row in rows) {
      final phone = row['whatsapp'] as String?;
      if (!_validPhone(phone) || row['consentimento_whatsapp'] != 1) {
        ignored++;
        continue;
      }
      final duplicate = await tx.query(
        'whatsapp_fila',
        columns: ['id'],
        where:
            "comercio_id=? AND agendamento_id=? AND template='lembrete_ia_hoje' AND status NOT IN ('falhou','cancelado')",
        whereArgs: [user.comercioId, row['id']],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        ignored++;
        continue;
      }
      try {
        final date = DateTime.parse(row['inicio'] as String).toLocal();
        final hour =
            '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
        await _whatsapp.enfileirar(
          txn: tx,
          comercioId: user.comercioId,
          destinatario: phone!,
          template: 'lembrete_ia_hoje',
          agendamentoId: row['id'] as String,
          payload: {
            'cliente': row['nome'],
            'hora': hour,
            'profissional': row['profissional'],
            'servico': row['servico'],
            'origem': 'helloa_sophia',
            'horario_permitido': '08:00-20:00',
          },
        );
        pending++;
      } catch (_) {
        failures++;
      }
    }
    return IaCommandResult(
      commandId: preview.id,
      recordId: preview.id,
      message:
          'Lembretes processados: $pending pendente(s), $failures falha(s), $ignored ignorado(s).',
      pending: pending,
      failures: failures,
      ignored: ignored,
    );
  }

  Future<IaCommandResult> _executeStock(
    DatabaseExecutor tx,
    UsuarioAcesso user,
    IaCommandPreview p,
  ) async {
    final code = p.fields['codigo_barras'] as String?;
    if (code != null) {
      final duplicates = await tx.query(
        'estoque',
        where: 'comercio_id=? AND codigo_barras=? AND ativo=1',
        whereArgs: [user.comercioId, code],
      );
      if (duplicates.isNotEmpty) {
        throw StateError(
          'Já existe produto com este código. Escolha adicionar quantidade, atualizar ou criar novo lote.',
        );
      }
    }
    final id = 'estoque_${IdGenerator.temporal()}';
    final now = DateTime.now().toUtc().toIso8601String();
    final name = [
      p.fields['produto'],
      p.fields['marca'],
      p.fields['cor'],
    ].whereType<String>().where((e) => e.isNotEmpty).join(' ');
    await tx.insert('estoque', {
      'id': id,
      'comercio_id': user.comercioId,
      'nome': name,
      'categoria': 'Outros',
      'tipo': 'produto',
      'quantidade_atual': p.fields['quantidade'],
      'estoque_minimo': 0,
      'unidade': 'un',
      'custo_unitario': p.fields['custo'] ?? 0,
      'preco_venda': p.fields['preco_venda'] ?? 0,
      'codigo_barras': code,
      'data_validade': p.fields['data_validade'],
      'ativo': 1,
      'descontar_automaticamente': 1,
      'estoque_destino': 'uso_interno',
      'data_cadastro': now,
    });
    if (p.fields['data_validade'] != null) {
      await tx.insert('estoque_lotes_ia', {
        'id': 'lote_${IdGenerator.temporal()}',
        'comercio_id': user.comercioId,
        'unidade_id': p.fields['unidade_id'],
        'estoque_id': id,
        'quantidade': p.fields['quantidade'],
        'data_validade': p.fields['data_validade'],
        'custo': p.fields['custo'],
        'preco_venda': p.fields['preco_venda'],
        'codigo_barras': code,
        'ativo': 1,
        'criado_em': now,
        'atualizado_em': now,
      });
    }
    await _sync(tx, user, id, 'estoque', 'upsert', p.fields);
    return _result(p, id, 'Produto cadastrado com ID $id.');
  }

  Future<IaCommandResult> _executeStockAddition(
    DatabaseExecutor tx,
    UsuarioAcesso user,
    IaCommandPreview p,
  ) async {
    final rows = await tx.query(
      'estoque',
      where: 'comercio_id=? AND ativo=1 AND LOWER(nome) LIKE ?',
      whereArgs: [user.comercioId, '%${p.fields['produto']}%'],
    );
    if (rows.length != 1) {
      throw StateError(
        rows.isEmpty
            ? 'Produto não encontrado.'
            : 'Há mais de um produto correspondente; escolha o registro exato.',
      );
    }
    final id = rows.single['id'] as String;
    final amount = (p.fields['quantidade'] as num).toDouble();
    await tx.rawUpdate(
      'UPDATE estoque SET quantidade_atual=quantidade_atual+? WHERE id=? AND comercio_id=?',
      [amount, id, user.comercioId],
    );
    await _sync(tx, user, id, 'estoque', 'upsert', {
      'quantidade_adicionada': amount,
    });
    return _result(p, id, 'Quantidade atualizada no produto $id.');
  }

  Future<IaCommandResult> _executeService(
    DatabaseExecutor tx,
    UsuarioAcesso user,
    IaCommandPreview p,
  ) async {
    final name = p.fields['nome'] as String;
    final duplicate = await tx.query(
      'servicos',
      columns: ['id'],
      where: 'comercio_id=? AND LOWER(nome)=?',
      whereArgs: [user.comercioId, name.toLowerCase()],
    );
    if (duplicate.isNotEmpty) {
      throw StateError('Já existe um serviço com este nome.');
    }
    final id = 'serv_${IdGenerator.temporal()}';
    final now = DateTime.now().toUtc().toIso8601String();
    await tx.insert('servicos', {
      'id': id,
      'comercio_id': user.comercioId,
      'nome': name,
      'categoria': 'Outros',
      'descricao': 'Criado pela Helloa Sophia',
      'preco': p.fields['preco'],
      'duracao_minutos': p.fields['duracao_minutos'],
      'ativo': 1,
      'custo_estimado': 0,
      'data_cadastro': now,
    });
    final professional = p.fields['profissional'] as String?;
    if (professional != null) {
      final rows = await tx.query(
        'profissionais',
        columns: ['id'],
        where: 'comercio_id=? AND ativo=1 AND LOWER(nome)=?',
        whereArgs: [user.comercioId, professional],
      );
      if (rows.length != 1) {
        throw StateError(
          'Profissional informado não encontrado de forma inequívoca.',
        );
      }
      await tx.insert('profissional_servicos', {
        'profissional_id': rows.single['id'],
        'servico_id': id,
      });
    }
    await _sync(tx, user, id, 'servico', 'upsert', p.fields);
    return _result(p, id, 'Serviço criado com ID $id.');
  }

  Future<IaCommandResult> _executeProfessional(
    DatabaseExecutor tx,
    UsuarioAcesso user,
    IaCommandPreview p,
  ) async {
    final name = p.fields['nome'] as String;
    final duplicate = await tx.query(
      'profissionais',
      columns: ['id'],
      where: 'comercio_id=? AND LOWER(nome)=?',
      whereArgs: [user.comercioId, name.toLowerCase()],
    );
    if (duplicate.isNotEmpty) {
      throw StateError('Já existe colaborador com este nome.');
    }
    final id = 'prof_${IdGenerator.temporal()}';
    final now = DateTime.now().toUtc().toIso8601String();
    final roles = (p.fields['funcoes'] as List).cast<String>();
    await tx.insert('profissionais', {
      'id': id,
      'comercio_id': user.comercioId,
      'nome': name,
      'whatsapp': '',
      'email': '',
      'cargo': roles.first,
      'foto_perfil': '',
      'ativo': 1,
      'percentual_comissao': 0,
      'meta_mensal': 0,
      'faturamento_mes': 0,
      'data_cadastro': now,
    });
    for (final role in roles) {
      final normalized = _slug(role);
      final functionId = 'func_${user.comercioId}_$normalized';
      await tx.insert('funcoes_profissionais', {
        'id': functionId,
        'comercio_id': user.comercioId,
        'nome': role,
        'nome_normalizado': normalized,
        'personalizada': 1,
        'ativo': 1,
        'criado_em': now,
        'atualizado_em': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await tx.insert('profissional_funcoes', {
        'comercio_id': user.comercioId,
        'profissional_id': id,
        'funcao_id': functionId,
        'ativo': 1,
        'atualizado_em': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await _sync(tx, user, id, 'profissional', 'upsert', p.fields);
    return _result(p, id, 'Colaborador criado com ID $id.');
  }

  Future<IaCommandResult> _executeExpense(
    DatabaseExecutor tx,
    UsuarioAcesso user,
    IaCommandPreview p,
  ) async {
    final id = 'mov_${IdGenerator.temporal()}';
    final now = DateTime.now().toUtc().toIso8601String();
    await tx.insert('movimentacoes_financeiras', {
      'id': id,
      'comercio_id': user.comercioId,
      'tipo': 'saida',
      'categoria': 'Materiais',
      'descricao': p.fields['descricao'],
      'valor': p.fields['valor'],
      'data': now,
      'status': 'pago',
      'forma_pagamento': 'não informado',
      'observacoes': 'Criado pela Helloa Sophia',
      'data_criacao': now,
    });
    await _sync(tx, user, id, 'movimentacao_financeira', 'upsert', p.fields);
    return _result(p, id, 'Saída de caixa criada com ID $id.');
  }

  IaCommandResult _result(IaCommandPreview p, String id, String message) =>
      IaCommandResult(commandId: p.id, recordId: id, message: message);
  Future<void> _audit(
    DatabaseExecutor db,
    UsuarioAcesso u,
    IaCommandPreview p,
    String action,
    String result,
  ) => db.insert('ia_auditoria', {
    'id': IdGenerator.temporal(),
    'comercio_id': u.comercioId,
    'usuario_id': u.id,
    'unidade_id': p.fields['unidade_id'],
    'intencao': p.intent,
    'acao': action,
    'confirmado': 1,
    'resultado': result,
    'criado_em': DateTime.now().toUtc().toIso8601String(),
  });
  Future<void> _sync(
    DatabaseExecutor db,
    UsuarioAcesso u,
    String id,
    String entity,
    String operation,
    Map<String, Object?> payload,
  ) {
    final now = DateTime.now().toUtc().toIso8601String();
    return db.insert('fila_sincronizacao', {
      'id': IdGenerator.temporal(),
      'comercio_id': u.comercioId,
      'unidade_id': payload['unidade_id'],
      'entidade': entity,
      'entidade_id': id,
      'operacao': operation,
      'payload_json': jsonEncode(payload),
      'status': 'pendente',
      'criada_em': now,
      'atualizada_em': now,
    });
  }

  UsuarioAcesso _user() {
    final user = SessionController.instance.usuario;
    if (user == null) {
      throw StateError('Sessão não autenticada.');
    }
    return user;
  }

  void _authorize(UsuarioAcesso u, String module) {
    final ok = switch (module) {
      'agenda' =>
        u.pode(ModuloPermissao.agenda) &&
            u.podeAcao(AcaoPermissao.gerenciarAgenda),
      'estoque' =>
        u.pode(ModuloPermissao.estoque) &&
            u.podeAcao(AcaoPermissao.movimentarEstoque),
      'servicos' => u.pode(ModuloPermissao.servicos),
      'funcionarios' => u.pode(ModuloPermissao.funcionarios),
      'financeiro' =>
        u.pode(ModuloPermissao.financeiro) &&
            u.podeAcao(AcaoPermissao.acessarFinanceiro),
      _ => false,
    };
    if (!ok) {
      throw StateError('Ação não autorizada para $module.');
    }
  }

  static bool _isReminderAction(String t) =>
      RegExp(r'\b(envie|mandar|dispare|enviar)\b').hasMatch(t) &&
      t.contains('lembrete') &&
      (t.contains('agendamento') || t.contains('agenda'));
  static bool _isStockCreate(String t) =>
      t.startsWith('cadastre') &&
      (t.contains('unidade') ||
          t.contains('estoque') ||
          t.contains('vencimento') ||
          t.contains('codigo')) &&
      !t.contains('como');
  static bool _isStockAdd(String t) =>
      RegExp(r'\b(acrescente|adicione)\b').hasMatch(t) &&
      (t.contains('estoque') || t.contains('unidade'));
  static bool _isServiceCreate(String t) =>
      RegExp(r'\b(crie|cadastre)\b').hasMatch(t) && t.contains('servico');
  static bool _isProfessionalCreate(String t) =>
      t.startsWith('cadastre') && t.contains(' como ');
  static bool _isFinanceCreate(String t) =>
      RegExp(r'\b(adicione|registre|lance)\b').hasMatch(t) &&
      t.contains('saida') &&
      t.contains('caixa');
  static String _normalize(String v) => v
      .toLowerCase()
      .replaceAll(RegExp('[áàãâ]'), 'a')
      .replaceAll(RegExp('[éê]'), 'e')
      .replaceAll(RegExp('[í]'), 'i')
      .replaceAll(RegExp('[óõô]'), 'o')
      .replaceAll(RegExp('[ú]'), 'u')
      .replaceAll('ç', 'c');
  static bool _validPhone(String? v) =>
      v != null && v.replaceAll(RegExp(r'\D'), '').length >= 10;
  static double? _number(String t, RegExp r) {
    final m = r.firstMatch(t)?.group(1);
    return m == null ? null : double.tryParse(m.replaceAll(',', '.'));
  }

  static double? _money(String t, String label) => _number(
    t,
    RegExp('(?:$label)\\s*(?:de\\s*)?(?:r.?\\s*)?(\\d+(?:[.,]\\d+)?)'),
  );
  static DateTime? _date(String t) {
    final m = RegExp(r'(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})').firstMatch(t);
    if (m == null) {
      return null;
    }
    var year = int.parse(m.group(3)!);
    if (year < 100) {
      year += 2000;
    }
    return DateTime.tryParse(
      '$year-${m.group(2)!.padLeft(2, '0')}-${m.group(1)!.padLeft(2, '0')}',
    );
  }

  static String? _between(String t, RegExp start, RegExp end) {
    final s = start.firstMatch(t);
    if (s == null) {
      return null;
    }
    final rest = t.substring(s.end);
    final e = end.firstMatch(rest);
    final value = (e == null ? rest : rest.substring(0, e.start)).trim();
    return value.isEmpty ? null : value;
  }

  static String? _afterWord(String t, String word) {
    final m = RegExp('$word\\s+([a-z0-9-]+)').firstMatch(t);
    return m?.group(1);
  }

  static String _slug(String t) => _normalize(
    t,
  ).replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');
  static String _idempotency(String commerce, String intent, String body) =>
      'ia_${commerce}_${intent}_${body.hashCode.abs()}';
}
