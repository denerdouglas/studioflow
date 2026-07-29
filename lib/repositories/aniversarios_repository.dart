import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../services/session_controller.dart';

class AniversarianteResumo {
  final String clienteId;
  final String nome;
  final String telefone;
  final DateTime nascimento;
  final DateTime cadastro;
  final DateTime? ultimoAtendimento;
  final double valorGasto;
  final String servicosFavoritos;

  const AniversarianteResumo({
    required this.clienteId,
    required this.nome,
    required this.telefone,
    required this.nascimento,
    required this.cadastro,
    required this.ultimoAtendimento,
    required this.valorGasto,
    required this.servicosFavoritos,
  });

  int? idadeEm(DateTime hoje) {
    if (nascimento.year < 1900) return null;
    var idade = hoje.year - nascimento.year;
    if (hoje.month < nascimento.month ||
        (hoje.month == nascimento.month && hoje.day < nascimento.day)) {
      idade--;
    }
    return idade >= 0 ? idade : null;
  }

  int mesesComoCliente(DateTime hoje) {
    final meses =
        (hoje.year - cadastro.year) * 12 + hoje.month - cadastro.month;
    return meses < 0 ? 0 : meses;
  }
}

class AniversariosRepository {
  final Future<Database> Function() _databaseProvider;
  final String? _comercioInformado;
  final String? _usuarioInformado;

  AniversariosRepository({
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

  Future<List<AniversarianteResumo>> listarDoDia([DateTime? referencia]) async {
    final hoje = referencia ?? DateTime.now();
    final db = await _databaseProvider();
    final clientes = await db.query(
      'clientes',
      where: 'comercio_id = ? AND ativo = 1 AND data_nascimento IS NOT NULL',
      whereArgs: [_comercioId],
      orderBy: 'nome COLLATE NOCASE',
    );
    final resultado = <AniversarianteResumo>[];
    for (final cliente in clientes) {
      final nascimento = DateTime.tryParse(
        cliente['data_nascimento'] as String? ?? '',
      );
      if (nascimento == null ||
          nascimento.month != hoje.month ||
          nascimento.day != hoje.day) {
        continue;
      }
      final clienteId = cliente['id'] as String;
      final atendimentos = await db.rawQuery(
        '''SELECT a.inicio, a.valor_recebido, s.nome AS servico_nome
           FROM agendamentos a
           LEFT JOIN servicos s ON s.id = a.servico_id
           WHERE a.comercio_id = ? AND a.cliente_id = ?
             AND a.status = 'concluido'
           ORDER BY a.inicio DESC''',
        [_comercioId, clienteId],
      );
      final contagem = <String, int>{};
      var recebido = 0.0;
      for (final item in atendimentos) {
        recebido += (item['valor_recebido'] as num? ?? 0).toDouble();
        final servico = item['servico_nome'] as String?;
        if (servico != null && servico.trim().isNotEmpty) {
          contagem[servico] = (contagem[servico] ?? 0) + 1;
        }
      }
      final favoritos = contagem.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      resultado.add(
        AniversarianteResumo(
          clienteId: clienteId,
          nome: cliente['nome'] as String,
          telefone: (cliente['whatsapp'] as String? ?? '').trim().isNotEmpty
              ? cliente['whatsapp'] as String
              : cliente['telefone'] as String? ?? '',
          nascimento: nascimento,
          cadastro:
              DateTime.tryParse(cliente['data_cadastro'] as String? ?? '') ??
              hoje,
          ultimoAtendimento: atendimentos.isEmpty
              ? null
              : DateTime.tryParse(
                  atendimentos.first['inicio'] as String? ?? '',
                ),
          valorGasto: recebido > 0
              ? recebido
              : (cliente['total_gasto'] as num? ?? 0).toDouble(),
          servicosFavoritos: favoritos.isEmpty
              ? 'Ainda sem histórico'
              : favoritos.take(3).map((item) => item.key).join(', '),
        ),
      );
    }
    return resultado;
  }

  Future<void> agendarContato({
    required String clienteId,
    required DateTime quando,
    String observacao = '',
  }) async {
    if (!quando.isAfter(DateTime.now())) {
      throw ArgumentError('Escolha uma data futura.');
    }
    final db = await _databaseProvider();
    final agora = DateTime.now().toUtc().toIso8601String();
    await db.insert('contatos_agendados', {
      'id': 'contato_${DateTime.now().microsecondsSinceEpoch}',
      'comercio_id': _comercioId,
      'cliente_id': clienteId,
      'tipo': 'aniversario',
      'agendado_para': quando.toUtc().toIso8601String(),
      'observacao': observacao.trim(),
      'status': 'pendente',
      'criado_por_id': _usuarioId,
      'criado_em': agora,
      'atualizado_em': agora,
    });
  }
}
