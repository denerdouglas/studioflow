import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../models/domain/infraestrutura.dart';
import '../services/session_controller.dart';

class InfraestruturaRepository {
  final Future<Database> Function() _databaseProvider;

  InfraestruturaRepository({Future<Database> Function()? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => DatabaseService.instance.database);

  String get _comercioId {
    final usuario = SessionController.instance.usuario;
    if (usuario == null) throw StateError('Entre em sua conta para continuar.');
    return usuario.comercioId;
  }

  Future<EstadoInfraestrutura> carregarEstado() async {
    final db = await _databaseProvider();
    final unidades = await db.query(
      'unidades',
      where: 'comercio_id = ? AND principal = 1 AND ativo = 1',
      whereArgs: [_comercioId],
      limit: 1,
    );
    if (unidades.isEmpty) {
      throw StateError('Unidade principal não encontrada após a migração.');
    }
    final integracoes = await db.query(
      'integracoes_configuracao',
      where: 'comercio_id = ?',
      whereArgs: [_comercioId],
      limit: 1,
    );
    final pendentes =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM fila_sincronizacao WHERE comercio_id = ? AND status = 'pendente'",
            [_comercioId],
          ),
        ) ??
        0;
    final erros =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM fila_sincronizacao WHERE comercio_id = ? AND status = 'erro'",
            [_comercioId],
          ),
        ) ??
        0;
    final sincronizados =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM fila_sincronizacao WHERE comercio_id = ? AND status = 'sincronizado' AND atualizada_em > ?",
            [
              _comercioId,
              DateTime.now()
                  .toUtc()
                  .subtract(const Duration(days: 1))
                  .toIso8601String(),
            ],
          ),
        ) ??
        0;
    final config = integracoes.isEmpty
        ? <String, Object?>{}
        : integracoes.first;
    return EstadoInfraestrutura(
      unidadePrincipal: UnidadeNegocio.fromMap(unidades.first),
      provedorBackend: config['provedor_backend'] as String? ?? 'nenhum',
      endpointPublico: config['endpoint_publico'] as String?,
      sincronizacaoAtiva: config['sincronizacao_ativa'] == 1,
      operacoesPendentes: pendentes,
      operacoesEmErro: erros,
      operacoesSincronizadas: sincronizados,
      ultimoCursor: config['ultimo_cursor'] as int? ?? 0,
      ultimaSincronizacao: DateTime.tryParse(
        config['ultima_sincronizacao'] as String? ?? '',
      ),
      ultimoErro: config['ultimo_erro'] as String?,
    );
  }

  Future<String> enfileirar({
    required String entidade,
    required String entidadeId,
    required String operacao,
    required Map<String, Object?> payload,
  }) async {
    if (entidade.trim().isEmpty || entidadeId.trim().isEmpty) {
      throw ArgumentError('Entidade e identificador são obrigatórios.');
    }
    const operacoesValidas = {'criar', 'atualizar', 'excluir'};
    if (!operacoesValidas.contains(operacao)) {
      throw ArgumentError('Operação de sincronização inválida.');
    }
    final estado = await carregarEstado();
    final id = 'sync_${IdGenerator.temporal()}';
    final agora = DateTime.now().toUtc().toIso8601String();
    final db = await _databaseProvider();
    await db.insert('fila_sincronizacao', {
      'id': id,
      'comercio_id': _comercioId,
      'unidade_id': estado.unidadePrincipal.id,
      'entidade': entidade.trim(),
      'entidade_id': entidadeId.trim(),
      'operacao': operacao,
      'payload_json': jsonEncode(payload),
      'versao_local': 1,
      'status': 'pendente',
      'tentativas': 0,
      'criada_em': agora,
      'atualizada_em': agora,
    });
    return id;
  }

  Future<List<OperacaoSincronizacao>> listarPendentes() async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'fila_sincronizacao',
      where: "comercio_id = ? AND status = 'pendente'",
      whereArgs: [_comercioId],
      orderBy: 'criada_em',
    );
    return rows
        .map(
          (row) => OperacaoSincronizacao(
            id: row['id'] as String,
            comercioId: row['comercio_id'] as String,
            unidadeId: row['unidade_id'] as String?,
            entidade: row['entidade'] as String,
            entidadeId: row['entidade_id'] as String,
            operacao: row['operacao'] as String,
            payloadJson: row['payload_json'] as String,
            versaoLocal: row['versao_local'] as int,
            status: row['status'] as String,
            tentativas: row['tentativas'] as int,
            ultimoErro: row['ultimo_erro'] as String?,
            criadaEm: DateTime.parse(row['criada_em'] as String),
          ),
        )
        .toList();
  }
}
