import 'package:sqflite/sqflite.dart';

/// Escrita transacional dos recebimentos de serviço.
///
/// A referência é o identificador idempotente do evento de pagamento, não do
/// atendimento. Assim, um atendimento pode receber várias parcelas sem que a
/// mesma confirmação seja contabilizada duas vezes.
abstract final class RecebimentoServicoWriter {
  static Future<bool> registrar(
    DatabaseExecutor db, {
    required String comercioId,
    required String agendamentoId,
    required double valor,
    required String formaPagamento,
    required String referencia,
    required String entidadeOrigem,
    String? usuarioId,
    DateTime? data,
  }) async {
    if (valor <= 0) return false;

    final existente = await db.query(
      'movimentacoes_financeiras',
      columns: ['id'],
      where:
          'comercio_id = ? AND entidade_origem = ? AND entidade_origem_id = ?',
      whereArgs: [comercioId, entidadeOrigem, referencia],
      limit: 1,
    );
    if (existente.isNotEmpty) return false;

    final agendas = await db.rawQuery(
      '''SELECT a.*, s.nome AS servico_nome
      FROM agendamentos a
      LEFT JOIN servicos s ON s.id=a.servico_id
      WHERE a.id=? AND a.comercio_id=? AND a.excluido=0 LIMIT 1''',
      [agendamentoId, comercioId],
    );
    if (agendas.isEmpty) throw StateError('Agendamento não encontrado.');
    final agenda = agendas.single;
    if (agenda['forma_pagamento'] == 'Pacote') {
      throw StateError('Sessão de pacote não recebe pagamento avulso.');
    }

    final total =
        ((agenda['valor_servico'] as num?)?.toDouble() ?? 0) -
        ((agenda['desconto'] as num?)?.toDouble() ?? 0);
    final recebido = (agenda['valor_recebido'] as num?)?.toDouble() ?? 0;
    if (valor - (total - recebido) > 0.005) {
      throw StateError('Valor recebido supera o saldo do atendimento.');
    }

    final agora = (data ?? DateTime.now()).toUtc().toIso8601String();
    await db.insert('movimentacoes_financeiras', {
      'id': 'recebimento_$referencia',
      'comercio_id': comercioId,
      'tipo': 'entrada',
      'descricao': 'Recebimento - ${agenda['servico_nome'] ?? 'Serviço'}',
      'valor': valor,
      'forma_pagamento': formaPagamento,
      'status': 'pago',
      'data': agora,
      'data_criacao': agora,
      'categoria': 'Serviços',
      'cliente_id': agenda['cliente_id'],
      'profissional_id': agenda['profissional_id'],
      'agendamento_id': agendamentoId,
      'servico_id': agenda['servico_id'],
      'usuario_responsavel_id': usuarioId,
      'observacoes': 'pagamento_confirmado',
      'centro_resultado': 'salao',
      'entidade_origem': entidadeOrigem,
      'entidade_origem_id': referencia,
    });
    await db.update(
      'agendamentos',
      {
        'valor_recebido': recebido + valor,
        'pagamento_status': recebido + valor >= total - 0.005
            ? 'pago'
            : 'parcial',
        'atualizado_em': agora,
      },
      where: 'id=? AND comercio_id=?',
      whereArgs: [agendamentoId, comercioId],
    );
    return true;
  }
}
