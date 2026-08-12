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
    if (_isLotExpiryUpdate(normalized)) {
      return _prepareLotExpiry(text, normalized);
    }
    if (_isProductInactivate(normalized)) {
      return _prepareProductInactivation(text, normalized);
    }
    if (_isServicePriceUpdate(normalized)) {
      return _prepareServicePrice(text, normalized);
    }
    if (_isUnitTransfer(normalized)) {
      return _prepareUnitTransfer(text, normalized, unitId);
    }
    if (_isStockCreate(normalized)) {
      return _prepareStock(text, normalized, unitId);
    }
    if (_isStockAdd(normalized)) {
      return _prepareStockAddition(text, normalized, unitId);
    }
    if (_isProfessionalModalityLink(normalized)) {
      return _prepareProfessionalModality(text, normalized);
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
          'vincular_profissional_modalidade' => _executeProfessionalModality(
            tx,
            user,
            preview,
          ),
          'criar_servico' => _executeService(tx, user, preview),
          'criar_colaborador' => _executeProfessional(tx, user, preview),
          'alterar_validade_lote' => _executeLotExpiry(tx, user, preview),
          'inativar_produto' => _executeProductInactivation(tx, user, preview),
          'alterar_preco_servico' => _executeServicePrice(tx, user, preview),
          'transferir_estoque_unidade' => _executeUnitTransfer(
            tx,
            user,
            preview,
          ),
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
    final fabrication = text.contains('fabricacao') ? _date(text) : null;
    final lot = _afterWord(text, 'lote');
    final internalCode = RegExp(
      r'codigo interno\s*([a-z0-9-]+)',
    ).firstMatch(text)?.group(1);
    final supplier = _afterWord(text, 'fornecedor');
    final minimum = _number(
      text,
      RegExp(r'estoque minimo\s*(\d+(?:[.,]\d+)?)'),
    );
    final measure =
        RegExp(r'\b(un|unidade|ml|l|g|kg)\b').firstMatch(text)?.group(1) ??
        'un';
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
        'data_fabricacao': fabrication?.toIso8601String(),
        'data_validade': expiry?.toIso8601String(),
        'lote': lot,
        'unidade_medida': measure,
        'codigo_barras': code,
        'codigo_interno': internalCode,
        'fornecedor': supplier,
        'estoque_minimo': minimum,
        'categoria_sugerida': _suggestCategory(name),
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
      RegExp(r',|\s+(?:duracao|na (?:area de )?)'),
    );
    final modality = RegExp(
      r'na (?:area de )?([a-z0-9 ]+?)(?:\.|,|$)',
    ).firstMatch(text)?.group(1)?.trim();
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
        'modalidade': modality,
        'texto_original': original,
      },
      [
        if (name == null) 'nome',
        if (duration == null) 'duração',
        if (price == null) 'preço',
      ],
    );
  }

  IaCommandPreview _prepareProfessionalModality(String original, String text) {
    final match = RegExp(
      r'vincule\s+([a-z ]+?)\s+(?:tambem\s+)?(?:a|na)\s+(?:area de\s+)?(.+?)(?:\.|$)',
    ).firstMatch(text);
    return _preview(
      'vincular_profissional_modalidade',
      'funcionarios',
      'Vincular colaborador à modalidade',
      {
        'profissional': match?.group(1)?.trim(),
        'modalidade': match?.group(2)?.trim(),
        'texto_original': original,
      },
      [
        if (match?.group(1) == null) 'colaborador',
        if (match?.group(2) == null) 'modalidade',
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

  IaCommandPreview _prepareLotExpiry(String original, String text) {
    final lot = RegExp(r'lote\s+([a-z0-9-]+)').firstMatch(text)?.group(1);
    final expiry = _date(text);
    return _preview(
      'alterar_validade_lote',
      'estoque',
      'Alterar vencimento do lote',
      {
        'lote': lot,
        'data_validade': expiry?.toIso8601String(),
        'texto_original': original,
      },
      [if (lot == null) 'lote', if (expiry == null) 'nova data de vencimento'],
    );
  }

  IaCommandPreview _prepareProductInactivation(String original, String text) {
    final rawName = RegExp(
      r'inative (?:o produto )?(.+?)(?:\.|$)',
    ).firstMatch(text)?.group(1)?.trim();
    final name = rawName
        ?.replaceFirst(RegExp(r'\s+lote\s+[a-z0-9-]+.*$'), '')
        .trim();
    return _preview(
      'inativar_produto',
      'estoque',
      'Inativar produto',
      {'produto': name, 'texto_original': original},
      [if (name == null) 'produto'],
    );
  }

  IaCommandPreview _prepareServicePrice(String original, String text) {
    final match = RegExp(
      r'(?:preco|valor) do servico\s+(.+?)\s+para\s+(?:r.?\s*)?(\d+(?:[.,]\d+)?)',
    ).firstMatch(text);
    return _preview(
      'alterar_preco_servico',
      'servicos',
      'Alterar preço do serviço',
      {
        'servico': match?.group(1)?.trim(),
        'preco': match == null
            ? null
            : double.tryParse(match.group(2)!.replaceAll(',', '.')),
        'texto_original': original,
      },
      [
        if (match?.group(1) == null) 'serviço',
        if (match?.group(2) == null) 'novo preço',
      ],
    );
  }

  IaCommandPreview _prepareUnitTransfer(
    String original,
    String text,
    String? sourceUnitId,
  ) {
    final quantity = _number(text, RegExp(r'transfira\s+(\d+(?:[.,]\d+)?)'));
    final product = RegExp(
      r'unidades? (?:do |de )?(.+?)\s+para (?:o )?estoque',
    ).firstMatch(text)?.group(1)?.trim();
    final destination = RegExp(
      r'estoque (?:da|de) unidade\s+([a-z0-9 -]+?)(?:\.|$)',
    ).firstMatch(text)?.group(1)?.trim();
    return _preview(
      'transferir_estoque_unidade',
      'estoque',
      'Transferir estoque entre unidades',
      {
        'unidade_origem_id': sourceUnitId,
        'unidade_destino': destination,
        'produto': product,
        'quantidade': quantity,
        'texto_original': original,
      },
      [
        if (sourceUnitId == null) 'unidade de origem ativa',
        if (destination == null) 'unidade de destino',
        if (product == null) 'produto',
        if (quantity == null) 'quantidade',
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
      final agendamentoId = row['id'] as String;
      final idempotency = '${agendamentoId}_lembrete_hoje';
      final duplicate = await tx.query(
        'whatsapp_fila',
        columns: ['id'],
        where: "business_id=? AND provider='system' AND idempotency_key=?",
        whereArgs: [user.comercioId, idempotency],
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
          idempotencyKey: idempotency,
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
      } catch (e) {
        failures++;
      }
    }
    return IaCommandResult(
      commandId: preview.id,
      recordId: preview.id,
      message:
          'Preparei $pending lembrete(s) e coloquei na fila. O envio ainda não foi confirmado. ($failures falhas, $ignored ignorados).',
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
    final now = DateTime.now().toUtc().toIso8601String();
    final amount = (p.fields['quantidade'] as num).toDouble();
    Map<String, Object?>? existing;
    if (code != null) {
      final duplicates = await tx.query(
        'estoque',
        where: 'comercio_id=? AND codigo_barras=? AND ativo=1',
        whereArgs: [user.comercioId, code],
      );
      if (duplicates.length > 1) {
        throw StateError(
          'Código duplicado em mais de um cadastro; escolha o registro exato.',
        );
      }
      if (duplicates.isNotEmpty) existing = duplicates.single;
    }
    if (existing != null) {
      if (p.fields['data_validade'] == null) {
        throw StateError(
          'Já existe produto com este código. Escolha adicionar quantidade, atualizar ou criar novo lote.',
        );
      }
      final sameLots = await tx.query(
        'estoque_lotes_ia',
        where:
            'comercio_id=? AND estoque_id=? AND COALESCE(unidade_id,\'\')=COALESCE(?,\'\') AND data_validade=? AND ativo=1',
        whereArgs: [
          user.comercioId,
          existing['id'],
          p.fields['unidade_id'],
          p.fields['data_validade'],
        ],
      );
      if (sameLots.isNotEmpty) {
        throw StateError(
          'Este produto já possui lote com o mesmo vencimento. Escolha adicionar quantidade ou atualizar o lote.',
        );
      }
      final lotId = 'lote_${IdGenerator.temporal()}';
      await _insertLot(tx, user, p, existing['id'] as String, lotId, now);
      await tx.rawUpdate(
        'UPDATE estoque SET quantidade_atual=quantidade_atual+? WHERE id=? AND comercio_id=?',
        [amount, existing['id'], user.comercioId],
      );
      await _sync(
        tx,
        user,
        existing['id'] as String,
        'estoque',
        'upsert',
        p.fields,
      );
      return _result(
        p,
        existing['id'] as String,
        'Novo lote $lotId criado no produto existente.',
      );
    }
    final id = 'estoque_${IdGenerator.temporal()}';
    final name = [
      p.fields['produto'],
      p.fields['marca'],
      p.fields['cor'],
    ].whereType<String>().where((e) => e.isNotEmpty).join(' ');
    await tx.insert('estoque', {
      'id': id,
      'comercio_id': user.comercioId,
      'nome': name,
      'categoria': p.fields['categoria_sugerida'] ?? 'Outros',
      'tipo': 'produto',
      'quantidade_atual': amount,
      'estoque_minimo': p.fields['estoque_minimo'] ?? 0,
      'unidade': p.fields['unidade_medida'] ?? 'un',
      'custo_unitario': p.fields['custo'] ?? 0,
      'fornecedor': p.fields['fornecedor'],
      'preco_venda': p.fields['preco_venda'] ?? 0,
      'codigo_barras': code,
      'codigo_interno': p.fields['codigo_interno'],
      'data_validade': p.fields['data_validade'],
      'ativo': 1,
      'descontar_automaticamente': 1,
      'estoque_destino': 'uso_interno',
      'observacoes': 'Criado pela Helloa Sophia',
      'data_cadastro': now,
    });
    if (p.fields['data_validade'] != null ||
        p.fields['lote'] != null ||
        p.fields['unidade_id'] != null) {
      await _insertLot(tx, user, p, id, 'lote_${IdGenerator.temporal()}', now);
    }
    await _sync(tx, user, id, 'estoque', 'upsert', p.fields);
    return _result(p, id, 'Produto cadastrado com ID $id.');
  }

  Future<void> _insertLot(
    DatabaseExecutor tx,
    UsuarioAcesso user,
    IaCommandPreview p,
    String stockId,
    String lotId,
    String now,
  ) => tx.insert('estoque_lotes_ia', {
    'id': lotId,
    'comercio_id': user.comercioId,
    'unidade_id': p.fields['unidade_id'],
    'estoque_id': stockId,
    'lote': p.fields['lote'],
    'quantidade': p.fields['quantidade'],
    'data_fabricacao': p.fields['data_fabricacao'],
    'data_validade': p.fields['data_validade'],
    'custo': p.fields['custo'],
    'preco_venda': p.fields['preco_venda'],
    'codigo_barras': p.fields['codigo_barras'],
    'codigo_interno': p.fields['codigo_interno'],
    'observacoes': 'Criado pela Helloa Sophia',
    'ativo': 1,
    'criado_em': now,
    'atualizado_em': now,
  });
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
    final modality = p.fields['modalidade'] as String?;
    if (modality != null) {
      final rows = await tx.query(
        'modalidades_estabelecimento',
        columns: ['id'],
        where: 'comercio_id=? AND ativa=1 AND nome_normalizado=?',
        whereArgs: [user.comercioId, _slug(modality)],
      );
      if (rows.length != 1) {
        throw StateError(
          'Modalidade informada não encontrada de forma inequívoca.',
        );
      }
      await tx.insert('modalidade_servicos', {
        'comercio_id': user.comercioId,
        'modalidade_id': rows.single['id'],
        'servico_id': id,
        'ativo': 1,
        'atualizado_em': now,
      });
    }
    await _sync(tx, user, id, 'servico', 'upsert', p.fields);
    return _result(p, id, 'Serviço criado com ID $id.');
  }

  Future<IaCommandResult> _executeProfessionalModality(
    DatabaseExecutor tx,
    UsuarioAcesso user,
    IaCommandPreview p,
  ) async {
    final professionals = await tx.query(
      'profissionais',
      columns: ['id', 'nome'],
      where: 'comercio_id=? AND ativo=1 AND LOWER(nome)=?',
      whereArgs: [user.comercioId, p.fields['profissional']],
    );
    final modalities = await tx.query(
      'modalidades_estabelecimento',
      columns: ['id', 'nome'],
      where: 'comercio_id=? AND ativa=1 AND nome_normalizado=?',
      whereArgs: [user.comercioId, _slug(p.fields['modalidade'] as String)],
    );
    if (professionals.length != 1 || modalities.length != 1) {
      throw StateError(
        'Colaborador ou modalidade não encontrado de forma inequívoca.',
      );
    }
    final professionalId = professionals.single['id'] as String;
    final modalityId = modalities.single['id'] as String;
    await tx.insert('modalidade_profissionais', {
      'comercio_id': user.comercioId,
      'modalidade_id': modalityId,
      'profissional_id': professionalId,
      'ativo': 1,
      'atualizado_em': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _sync(
      tx,
      user,
      professionalId,
      'modalidade_profissionais',
      'upsert',
      p.fields,
    );
    return _result(
      p,
      professionalId,
      'Colaborador vinculado à modalidade ${modalities.single['nome']}.',
    );
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

  Future<IaCommandResult> _executeLotExpiry(
    DatabaseExecutor tx,
    UsuarioAcesso user,
    IaCommandPreview p,
  ) async {
    final lot = p.fields['lote'] as String;
    final rows = await tx.query(
      'estoque_lotes_ia',
      where: 'comercio_id=? AND ativo=1 AND (LOWER(lote)=? OR LOWER(id)=?)',
      whereArgs: [user.comercioId, lot.toLowerCase(), lot.toLowerCase()],
    );
    if (rows.length != 1) {
      throw StateError(
        rows.isEmpty
            ? 'Lote não encontrado. Nenhuma alteração foi realizada.'
            : 'Mais de um lote corresponde ao código informado.',
      );
    }
    final id = rows.single['id'] as String;
    await tx.update(
      'estoque_lotes_ia',
      {
        'data_validade': p.fields['data_validade'],
        'atualizado_em': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id=? AND comercio_id=?',
      whereArgs: [id, user.comercioId],
    );
    await _sync(tx, user, id, 'estoque_lote', 'upsert', p.fields);
    return _result(p, id, 'Vencimento do lote $id atualizado.');
  }

  Future<IaCommandResult> _executeProductInactivation(
    DatabaseExecutor tx,
    UsuarioAcesso user,
    IaCommandPreview p,
  ) async {
    final rows = await tx.query(
      'estoque',
      columns: ['id', 'nome'],
      where: 'comercio_id=? AND ativo=1 AND LOWER(nome) LIKE ?',
      whereArgs: [user.comercioId, '%${p.fields['produto']}%'],
    );
    if (rows.length != 1) {
      throw StateError(
        rows.isEmpty
            ? 'Produto não encontrado.'
            : 'Há mais de um produto correspondente; informe o registro exato.',
      );
    }
    final id = rows.single['id'] as String;
    await tx.update(
      'estoque',
      {'ativo': 0},
      where: 'id=? AND comercio_id=?',
      whereArgs: [id, user.comercioId],
    );
    await _sync(tx, user, id, 'estoque', 'upsert', {'ativo': false});
    return _result(p, id, 'Produto ${rows.single['nome']} inativado.');
  }

  Future<IaCommandResult> _executeServicePrice(
    DatabaseExecutor tx,
    UsuarioAcesso user,
    IaCommandPreview p,
  ) async {
    final rows = await tx.query(
      'servicos',
      columns: ['id', 'nome'],
      where: 'comercio_id=? AND LOWER(nome) LIKE ?',
      whereArgs: [user.comercioId, '%${p.fields['servico']}%'],
    );
    if (rows.length != 1) {
      throw StateError(
        rows.isEmpty
            ? 'Serviço não encontrado.'
            : 'Há mais de um serviço correspondente; informe o registro exato.',
      );
    }
    final id = rows.single['id'] as String;
    await tx.update(
      'servicos',
      {'preco': p.fields['preco']},
      where: 'id=? AND comercio_id=?',
      whereArgs: [id, user.comercioId],
    );
    await _sync(tx, user, id, 'servico', 'upsert', {
      'preco': p.fields['preco'],
    });
    return _result(
      p,
      id,
      'Preço do serviço ${rows.single['nome']} atualizado.',
    );
  }

  Future<IaCommandResult> _executeUnitTransfer(
    DatabaseExecutor tx,
    UsuarioAcesso user,
    IaCommandPreview p,
  ) async {
    final sourceUnitId = p.fields['unidade_origem_id'] as String;
    final destinationText = (p.fields['unidade_destino'] as String)
        .toLowerCase();
    final units = await tx.query(
      'unidades',
      columns: ['id', 'nome', 'codigo'],
      where: 'comercio_id=? AND ativo=1',
      whereArgs: [user.comercioId],
      orderBy: 'principal DESC, nome COLLATE NOCASE',
    );
    Map<String, Object?>? destination;
    final position = int.tryParse(destinationText);
    if (position != null && position > 0 && position <= units.length) {
      destination = units[position - 1];
    } else {
      for (final unit in units) {
        final name = (unit['nome'] as String).toLowerCase();
        final code = (unit['codigo'] as String? ?? '').toLowerCase();
        if (name == destinationText || code == destinationText) {
          destination = unit;
          break;
        }
      }
    }
    if (destination == null) {
      throw StateError('Unidade de destino não encontrada.');
    }
    final destinationId = destination['id'] as String;
    if (destinationId == sourceUnitId) {
      throw StateError('A unidade de destino deve ser diferente da origem.');
    }
    final products = await tx.query(
      'estoque',
      columns: ['id', 'nome'],
      where: 'comercio_id=? AND ativo=1 AND LOWER(nome) LIKE ?',
      whereArgs: [user.comercioId, '%${p.fields['produto']}%'],
    );
    if (products.length != 1) {
      throw StateError(
        products.isEmpty
            ? 'Produto não encontrado.'
            : 'Há mais de um produto correspondente; informe o registro exato.',
      );
    }
    final productId = products.single['id'] as String;
    final amount = (p.fields['quantidade'] as num).toDouble();
    final sourceLots = await tx.query(
      'estoque_lotes_ia',
      where:
          'comercio_id=? AND unidade_id=? AND estoque_id=? AND ativo=1 AND quantidade>=?',
      whereArgs: [user.comercioId, sourceUnitId, productId, amount],
      orderBy: 'data_validade, criado_em',
      limit: 1,
    );
    if (sourceLots.isEmpty) {
      throw StateError('Saldo por lote insuficiente na unidade de origem.');
    }
    final source = sourceLots.single;
    final sourceId = source['id'] as String;
    await tx.update(
      'estoque_lotes_ia',
      {
        'quantidade': (source['quantidade'] as num).toDouble() - amount,
        'atualizado_em': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id=? AND comercio_id=?',
      whereArgs: [sourceId, user.comercioId],
    );
    final targetLots = await tx.query(
      'estoque_lotes_ia',
      where:
          'comercio_id=? AND unidade_id=? AND estoque_id=? AND COALESCE(lote,\'\')=COALESCE(?,\'\') AND ativo=1',
      whereArgs: [
        user.comercioId,
        destinationId,
        productId,
        source['lote'] ?? '',
      ],
      limit: 1,
    );
    final targetId = targetLots.isEmpty
        ? 'lote_${IdGenerator.temporal()}'
        : targetLots.single['id'] as String;
    if (targetLots.isEmpty) {
      await tx.insert('estoque_lotes_ia', {
        ...source,
        'id': targetId,
        'unidade_id': destinationId,
        'quantidade': amount,
        'criado_em': DateTime.now().toUtc().toIso8601String(),
        'atualizado_em': DateTime.now().toUtc().toIso8601String(),
      });
    } else {
      await tx.update(
        'estoque_lotes_ia',
        {
          'quantidade':
              (targetLots.single['quantidade'] as num).toDouble() + amount,
          'atualizado_em': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id=? AND comercio_id=?',
        whereArgs: [targetId, user.comercioId],
      );
    }
    await _sync(tx, user, productId, 'estoque_transferencia', 'upsert', {
      ...p.fields,
      'unidade_destino_id': destinationId,
      'lote_origem_id': sourceId,
      'lote_destino_id': targetId,
    });
    return _result(
      p,
      productId,
      'Transferência registrada para ${destination['nome']}.',
    );
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
  static bool _isLotExpiryUpdate(String t) =>
      RegExp(r'\b(altere|corrija)\b').hasMatch(t) &&
      t.contains('vencimento') &&
      t.contains('lote');
  static bool _isProductInactivate(String t) =>
      t.startsWith('inative') && t.contains('produto');
  static bool _isServicePriceUpdate(String t) =>
      RegExp(r'\b(corrija|altere)\b').hasMatch(t) &&
      (t.contains('preco') || t.contains('valor')) &&
      t.contains('servico');
  static bool _isUnitTransfer(String t) =>
      t.startsWith('transfira') &&
      t.contains('estoque') &&
      t.contains('unidade');
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
  static bool _isProfessionalModalityLink(String t) =>
      t.startsWith('vincule') && t.contains('area');
  static bool _isServiceCreate(String t) =>
      RegExp(r'\b(crie|cadastre)\b').hasMatch(t) && t.contains('servico');
  static bool _isProfessionalCreate(String t) =>
      t.startsWith('cadastre') && t.contains(' como ');
  static bool _isFinanceCreate(String t) =>
      RegExp(r'\b(adicione|registre|lance)\b').hasMatch(t) &&
      t.contains('saida') &&
      t.contains('caixa');
  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp('[áàãâ]'), 'a')
      .replaceAll(RegExp('[éê]'), 'e')
      .replaceAll('í', 'i')
      .replaceAll(RegExp('[óõô]'), 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'\bcadastra\b|\bcadatra\b'), 'cadastre')
      .replaceAll(RegExp(r'\badcion(e|a)\b'), 'adicione')
      .replaceAll(RegExp(r'\bacrecente\b'), 'acrescente');
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
  static DateTime? _date(String text) {
    final numeric = RegExp(
      r'(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})',
    ).firstMatch(text);
    if (numeric != null) {
      var year = int.parse(numeric.group(3)!);
      if (year < 100) year += 2000;
      return DateTime.tryParse(
        '$year-${numeric.group(2)!.padLeft(2, '0')}-${numeric.group(1)!.padLeft(2, '0')}',
      );
    }
    final written = RegExp(
      r'(\d{1,2})\s+de\s+(janeiro|fevereiro|marco|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro)\s+de\s+(\d{4})',
    ).firstMatch(text);
    if (written == null) return null;
    const months = <String, int>{
      'janeiro': 1,
      'fevereiro': 2,
      'marco': 3,
      'abril': 4,
      'maio': 5,
      'junho': 6,
      'julho': 7,
      'agosto': 8,
      'setembro': 9,
      'outubro': 10,
      'novembro': 11,
      'dezembro': 12,
    };
    return DateTime(
      int.parse(written.group(3)!),
      months[written.group(2)]!,
      int.parse(written.group(1)!),
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

  static String _suggestCategory(String? name) {
    final value = name ?? '';
    if (RegExp(r'esmalte|lixa|unha|acetona').hasMatch(value)) return 'Unhas';
    if (RegExp(r'shampoo|condicionador|cabelo').hasMatch(value)) {
      return 'Cabelo';
    }
    if (RegExp(r'luva|mascara|alcool').hasMatch(value)) return 'Consumíveis';
    return 'Outros';
  }

  static String _slug(String t) => _normalize(
    t,
  ).replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');
  static String _idempotency(String commerce, String intent, String body) =>
      'ia_${commerce}_${intent}_${body.hashCode.abs()}';
}
