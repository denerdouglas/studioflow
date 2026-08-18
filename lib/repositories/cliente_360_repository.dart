import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../models/domain/atendimento.dart';
import '../services/session_controller.dart';
import 'central_comandas_repository.dart';

class Cliente360Repository {
  final Future<Database> Function() _databaseProvider;
  final String? _comercioInformado;

  Cliente360Repository({
    Future<Database> Function()? databaseProvider,
    String? comercioId,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseService.instance.database),
       _comercioInformado = comercioId;

  String get _comercioId =>
      _comercioInformado ?? SessionController.instance.usuario!.comercioId;

  Future<List<Map<String, Object?>>> listarClientes() async {
    final db = await _databaseProvider();
    return db.query(
      'clientes',
      columns: ['id', 'nome', 'whatsapp', 'email'],
      where: 'comercio_id = ? AND ativo = 1',
      whereArgs: [_comercioId],
      orderBy: 'nome COLLATE NOCASE',
    );
  }

  Future<ResumoCliente360> carregar(String clienteId) async {
    final db = await _databaseProvider();
    final clientes = await db.rawQuery(
      '''SELECT c.*, p.nome AS profissional_preferido_nome
         FROM clientes c
         LEFT JOIN profissionais p ON p.id = COALESCE(
           c.profissional_preferido_id, c.profissional_principal_id)
         WHERE c.id = ? AND c.comercio_id = ? LIMIT 1''',
      [clienteId, _comercioId],
    );
    if (clientes.isEmpty) throw StateError('Cliente não encontrado.');
    final agenda = await db.rawQuery(
      '''SELECT a.id, a.inicio, a.status, a.valor_servico, a.valor_recebido,
                s.nome AS servico_nome, p.nome AS profissional_nome
         FROM agendamentos a
         JOIN servicos s ON s.id = a.servico_id
         JOIN profissionais p ON p.id = a.profissional_id
         WHERE a.comercio_id = ? AND a.cliente_id = ? AND a.excluido = 0
         ORDER BY a.inicio DESC''',
      [_comercioId, clienteId],
    );
    final central = CentralComandasRepository(
      databaseProvider: _databaseProvider,
      comercioId: _comercioId,
    );
    final comprasAtuais = await central.listar(clienteId: clienteId);
    final resumoCompras = await central.resumoCliente(clienteId);
    final comprasLegadas = await db.rawQuery(
      '''SELECT v.id, v.numero, v.total, v.status, v.criada_em,
                GROUP_CONCAT(i.nome_produto || ' x' || i.quantidade) AS itens
         FROM vendas v
         LEFT JOIN venda_itens i ON i.venda_id = v.id AND i.comercio_id = v.comercio_id
         WHERE v.comercio_id = ? AND v.cliente_id = ?
         GROUP BY v.id ORDER BY v.criada_em DESC''',
      [_comercioId, clienteId],
    );
    final compras =
        <Map<String, Object?>>[
          ...comprasAtuais,
          ...comprasLegadas.map(
            (row) => {
              ...row,
              'data_venda': row['criada_em'],
              'status_central': row['status'],
              'origem_registro': 'legado',
              'itens_busca': row['itens'],
            },
          ),
        ]..sort(
          (a, b) => '${b['data_venda'] ?? b['criada_em']}'.compareTo(
            '${a['data_venda'] ?? a['criada_em']}',
          ),
        );
    final c = clientes.first;
    double recebido = 0;
    var faltas = 0;
    var cancelamentos = 0;
    for (final item in agenda) {
      recebido += (item['valor_recebido'] as num? ?? 0).toDouble();
      if (item['status'] == 'faltou') faltas++;
      if (item['status'] == 'cancelado') cancelamentos++;
    }
    final comprasLegadasValidas = comprasLegadas
        .where((row) => row['status'] != 'cancelada')
        .toList();
    final totalLegado = comprasLegadasValidas.fold<double>(
      0,
      (sum, row) => sum + (row['total'] as num? ?? 0).toDouble(),
    );
    final comprasTotal =
        (resumoCompras['total_comprado'] as num? ?? 0).toDouble() + totalLegado;
    final quantidadeCompras =
        (resumoCompras['quantidade_compras'] as num? ?? 0).toInt() +
        comprasLegadasValidas.length;
    return ResumoCliente360(
      clienteId: clienteId,
      nome: c['nome'] as String,
      whatsapp: c['whatsapp'] as String? ?? '',
      telefone: c['telefone'] as String? ?? '',
      instagram:
          (c.containsKey('instagram') ? c['instagram'] as String? : null) ?? '',
      email: c['email'] as String? ?? '',
      aniversario: DateTime.tryParse(c['data_nascimento'] as String? ?? ''),
      profissionalPreferido:
          c['profissional_preferido_nome'] as String? ?? 'Não definido',
      agendamentos: agenda.length,
      faltas: faltas,
      cancelamentos: cancelamentos,
      recebidoServicos: recebido,
      comprasProdutos: comprasTotal,
      quantidadeCompras: quantidadeCompras,
      ticketMedioCompras: quantidadeCompras == 0
          ? 0
          : comprasTotal / quantidadeCompras,
      totalComprasEmAberto: (resumoCompras['total_em_aberto'] as num? ?? 0)
          .toDouble(),
      ultimaCompra: DateTime.tryParse(
        '${resumoCompras['ultima_compra'] ?? ''}',
      ),
      historicoAgenda: agenda,
      historicoCompras: compras,
    );
  }

  Future<void> atualizarPreferencias({
    required String clienteId,
    String? profissionalPreferidoId,
    required bool consentimentoWhatsapp,
    required bool consentimentoMarketing,
  }) async {
    final db = await _databaseProvider();
    final alterados = await db.update(
      'clientes',
      {
        'profissional_preferido_id': profissionalPreferidoId,
        'consentimento_whatsapp': consentimentoWhatsapp ? 1 : 0,
        'consentimento_marketing': consentimentoMarketing ? 1 : 0,
        'atualizado_em': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [clienteId, _comercioId],
    );
    if (alterados == 0) throw StateError('Cliente não encontrado.');
  }
}
