import 'package:sqflite/sqflite.dart';

import 'database_service.dart';
import '../services/session_controller.dart';

class MovimentacaoFidelidadeRegistro {
  final String id;
  final String clienteId;
  final String tipo;
  final int pontos;
  final String descricao;
  final String? agendamentoId;
  final DateTime dataCriacao;

  const MovimentacaoFidelidadeRegistro({
    required this.id,
    required this.clienteId,
    required this.tipo,
    required this.pontos,
    required this.descricao,
    required this.agendamentoId,
    required this.dataCriacao,
  });

  bool get ehCredito => tipo == 'credito';

  bool get ehResgate => tipo == 'resgate';

  Map<String, Object?> paraMapa() {
    return {
      'id': id,
      'cliente_id': clienteId,
      'tipo': tipo,
      'pontos': pontos,
      'descricao': descricao,
      'agendamento_id': agendamentoId,
      'data_criacao': dataCriacao.toIso8601String(),
    };
  }

  factory MovimentacaoFidelidadeRegistro.doMapa(Map<String, Object?> mapa) {
    return MovimentacaoFidelidadeRegistro(
      id: mapa['id'] as String,
      clienteId: mapa['cliente_id'] as String? ?? '',
      tipo: mapa['tipo'] as String? ?? 'credito',
      pontos: (mapa['pontos'] as num? ?? 0).toInt(),
      descricao: mapa['descricao'] as String? ?? 'Movimentação de pontos',
      agendamentoId: mapa['agendamento_id'] as String?,
      dataCriacao:
          DateTime.tryParse(mapa['data_criacao'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class RecompensaFidelidadeRegistro {
  final String id;
  final String nome;
  final String descricao;
  final int pontosNecessarios;
  final double desconto;
  final bool ativo;
  final DateTime dataCadastro;

  const RecompensaFidelidadeRegistro({
    required this.id,
    required this.nome,
    required this.descricao,
    required this.pontosNecessarios,
    required this.desconto,
    required this.ativo,
    required this.dataCadastro,
  });

  Map<String, Object?> paraMapa() {
    return {
      'id': id,
      'nome': nome,
      'descricao': descricao,
      'pontos_necessarios': pontosNecessarios,
      'desconto': desconto,
      'ativo': ativo ? 1 : 0,
      'data_cadastro': dataCadastro.toIso8601String(),
    };
  }

  factory RecompensaFidelidadeRegistro.doMapa(Map<String, Object?> mapa) {
    return RecompensaFidelidadeRegistro(
      id: mapa['id'] as String,
      nome: mapa['nome'] as String? ?? 'Recompensa',
      descricao: mapa['descricao'] as String? ?? '',
      pontosNecessarios: (mapa['pontos_necessarios'] as num? ?? 0).toInt(),
      desconto: (mapa['desconto'] as num? ?? 0).toDouble(),
      ativo: (mapa['ativo'] as num? ?? 1) == 1,
      dataCadastro:
          DateTime.tryParse(mapa['data_cadastro'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class ResumoFidelidade {
  final int clientesComPontos;
  final int pontosDistribuidos;
  final int pontosResgatados;
  final int recompensasAtivas;

  const ResumoFidelidade({
    required this.clientesComPontos,
    required this.pontosDistribuidos,
    required this.pontosResgatados,
    required this.recompensasAtivas,
  });

  factory ResumoFidelidade.vazio() {
    return const ResumoFidelidade(
      clientesComPontos: 0,
      pontosDistribuidos: 0,
      pontosResgatados: 0,
      recompensasAtivas: 0,
    );
  }
}

class FidelidadeRepository {
  final DatabaseService _databaseService;

  FidelidadeRepository({DatabaseService? databaseService})
    : _databaseService = databaseService ?? DatabaseService.instance;

  Future<Database> get _db async => _databaseService.database;
  String get _comercioId => SessionController.instance.usuario!.comercioId;

  Future<void> garantirEstrutura() async {
    final db = await _db;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS movimentacoes_fidelidade (
        id TEXT PRIMARY KEY,
        comercio_id TEXT NOT NULL,
        cliente_id TEXT NOT NULL,
        tipo TEXT NOT NULL,
        pontos INTEGER NOT NULL,
        descricao TEXT NOT NULL,
        agendamento_id TEXT,
        data_criacao TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS recompensas_fidelidade (
        id TEXT PRIMARY KEY,
        comercio_id TEXT NOT NULL,
        nome TEXT NOT NULL,
        descricao TEXT,
        pontos_necessarios INTEGER NOT NULL,
        desconto REAL NOT NULL DEFAULT 0,
        ativo INTEGER NOT NULL DEFAULT 1,
        data_cadastro TEXT NOT NULL
      )
    ''');

    for (final tabela in [
      'movimentacoes_fidelidade',
      'recompensas_fidelidade',
    ]) {
      final colunas = await db.rawQuery('PRAGMA table_info($tabela)');
      if (!colunas.any((c) => c['name'] == 'comercio_id')) {
        await db.execute(
          "ALTER TABLE $tabela ADD COLUMN comercio_id TEXT NOT NULL DEFAULT 'comercio_legado'",
        );
      }
    }

    await db.execute('''
      CREATE INDEX IF NOT EXISTS
      idx_fidelidade_cliente
      ON movimentacoes_fidelidade (cliente_id)
    ''');
  }

  Future<List<MovimentacaoFidelidadeRegistro>> listarMovimentacoes({
    String? clienteId,
  }) async {
    await garantirEstrutura();

    final db = await _db;

    final resultado = await db.query(
      'movimentacoes_fidelidade',
      where: clienteId == null
          ? 'comercio_id = ?'
          : 'cliente_id = ? AND comercio_id = ?',
      whereArgs: clienteId == null ? [_comercioId] : [clienteId, _comercioId],
      orderBy: 'data_criacao DESC',
    );

    return resultado.map(MovimentacaoFidelidadeRegistro.doMapa).toList();
  }

  Future<List<RecompensaFidelidadeRegistro>> listarRecompensas({
    bool incluirInativas = true,
  }) async {
    await garantirEstrutura();

    final db = await _db;

    final resultado = await db.query(
      'recompensas_fidelidade',
      where: incluirInativas
          ? 'comercio_id = ?'
          : 'ativo = ? AND comercio_id = ?',
      whereArgs: incluirInativas ? [_comercioId] : [1, _comercioId],
      orderBy: 'pontos_necessarios ASC',
    );

    return resultado.map(RecompensaFidelidadeRegistro.doMapa).toList();
  }
}
