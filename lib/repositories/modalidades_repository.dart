import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../models/domain/acesso.dart';
import '../services/session_controller.dart';

class ModalidadeRegistro {
  final String id;
  final String nome;
  final String descricao;
  final String icone;
  final String imagemCapa;
  final String cor;
  final int ordem;
  final bool favorita;
  final bool exibirHome;
  final bool ativa;
  final bool personalizada;

  const ModalidadeRegistro({
    required this.id,
    required this.nome,
    this.descricao = '',
    this.icone = 'category',
    this.imagemCapa = '',
    this.cor = '#8E5CE6',
    this.ordem = 0,
    this.favorita = false,
    this.exibirHome = true,
    this.ativa = true,
    this.personalizada = true,
  });

  factory ModalidadeRegistro.fromMap(Map<String, Object?> map) =>
      ModalidadeRegistro(
        id: map['id'] as String,
        nome: map['nome'] as String,
        descricao: map['descricao'] as String? ?? '',
        icone: map['icone'] as String? ?? 'category',
        imagemCapa: map['imagem_capa'] as String? ?? '',
        cor: map['cor'] as String? ?? '#8E5CE6',
        ordem: map['ordem'] as int? ?? 0,
        favorita: map['favorita'] == 1,
        exibirHome: map['exibir_home'] != 0,
        ativa: map['ativa'] != 0,
        personalizada: map['personalizada'] != 0,
      );
}

class ModalidadeExclusaoException implements Exception {
  final String message;
  const ModalidadeExclusaoException(this.message);
  @override
  String toString() => message;
}

class ModalidadesRepository {
  final Future<Database> Function() _databaseProvider;
  final String? _commerceId;
  final String? _userId;

  ModalidadesRepository({
    Future<Database> Function()? databaseProvider,
    String? comercioId,
    String? usuarioId,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseService.instance.database),
       _commerceId = comercioId,
       _userId = usuarioId;

  String get comercioId =>
      _commerceId ?? SessionController.instance.usuario!.comercioId;
  String get usuarioId => _userId ?? SessionController.instance.usuario!.id;

  void _authorize() {
    if (_commerceId != null) return;
    final user = SessionController.instance.usuario;
    if (user == null || !user.pode(ModuloPermissao.configuracoes)) {
      throw StateError('Sem permissão para gerenciar modalidades.');
    }
  }

  Future<List<ModalidadeRegistro>> listar({bool incluirInativas = true}) async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'modalidades_estabelecimento',
      where: incluirInativas ? 'comercio_id=?' : 'comercio_id=? AND ativa=1',
      whereArgs: [comercioId],
      orderBy: 'ordem, nome COLLATE NOCASE',
    );
    return rows.map(ModalidadeRegistro.fromMap).toList();
  }

  Future<String> salvar(ModalidadeRegistro item) async {
    _authorize();
    final name = item.nome.trim();
    if (name.isEmpty) throw ArgumentError('Informe o nome da modalidade.');
    final db = await _databaseProvider();
    final id = item.id.isEmpty ? 'mod_${IdGenerator.temporal()}' : item.id;
    final normalized = _normalize(name);
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((tx) async {
      final duplicate = await tx.query(
        'modalidades_estabelecimento',
        columns: ['id'],
        where: 'comercio_id=? AND nome_normalizado=? AND id!=?',
        whereArgs: [comercioId, normalized, id],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        throw StateError('Já existe uma modalidade com este nome.');
      }
      await tx.insert(
        'modalidades_estabelecimento',
        {
          'id': id,
          'comercio_id': comercioId,
          'nome': name,
          'nome_normalizado': normalized,
          'descricao': item.descricao.trim(),
          'icone': item.icone,
          'imagem_capa': item.imagemCapa.trim(),
          'cor': item.cor,
          'ordem': item.ordem,
          'favorita': item.favorita ? 1 : 0,
          'exibir_home': item.exibirHome ? 1 : 0,
          'ativa': item.ativa ? 1 : 0,
          'personalizada': item.personalizada ? 1 : 0,
          'criado_em': now,
          'atualizado_em': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _sync(tx, id, 'upsert', {'nome': name, 'ativa': item.ativa});
      await _audit(tx, item.id.isEmpty ? 'criar' : 'editar', id);
    });
    return id;
  }

  Future<void> alterarStatus(String id, bool active) async {
    _authorize();
    final db = await _databaseProvider();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((tx) async {
      final changed = await tx.update(
        'modalidades_estabelecimento',
        {'ativa': active ? 1 : 0, 'atualizado_em': now},
        where: 'id=? AND comercio_id=?',
        whereArgs: [id, comercioId],
      );
      if (changed != 1) throw StateError('Modalidade não encontrada.');
      await _sync(tx, id, 'upsert', {'ativa': active});
      await _audit(tx, active ? 'reativar' : 'inativar', id);
    });
  }

  Future<void> reordenar(List<String> ids) async {
    _authorize();
    final db = await _databaseProvider();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((tx) async {
      for (var index = 0; index < ids.length; index++) {
        await tx.update(
          'modalidades_estabelecimento',
          {'ordem': index, 'atualizado_em': now},
          where: 'id=? AND comercio_id=?',
          whereArgs: [ids[index], comercioId],
        );
      }
      await _sync(tx, 'ordem', 'reorder', {'ids': ids});
    });
  }

  Future<void> excluir(String id) async {
    _authorize();
    final db = await _databaseProvider();
    await db.transaction((tx) async {
      final counts = await Future.wait([
        _count(tx, 'modalidade_servicos', id),
        _count(tx, 'modalidade_profissionais', id),
        _count(tx, 'modalidade_estoque', id),
        _count(tx, 'modalidade_funcoes', id),
      ]);
      if (counts.any((count) => count > 0)) {
        throw const ModalidadeExclusaoException(
          'A modalidade possui vínculos ou histórico. Inative para preservar agenda, estoque e financeiro.',
        );
      }
      final deleted = await tx.delete(
        'modalidades_estabelecimento',
        where: 'id=? AND comercio_id=?',
        whereArgs: [id, comercioId],
      );
      if (deleted != 1) throw StateError('Modalidade não encontrada.');
      await _sync(tx, id, 'delete', const {});
      await _audit(tx, 'excluir', id);
    });
  }

  Future<void> vincularServico(String modalidadeId, String servicoId) =>
      _link('modalidade_servicos', modalidadeId, 'servico_id', servicoId);
  Future<void> vincularProfissional(
    String modalidadeId,
    String profissionalId,
  ) => _link(
    'modalidade_profissionais',
    modalidadeId,
    'profissional_id',
    profissionalId,
  );
  Future<void> vincularEstoque(String modalidadeId, String estoqueId) =>
      _link('modalidade_estoque', modalidadeId, 'estoque_id', estoqueId);

  Future<Map<String, List<Map<String, Object?>>>> opcoesVinculos(
    String modalidadeId,
  ) async {
    final db = await _databaseProvider();
    Future<List<Map<String, Object?>>> load(
      String source,
      String link,
      String foreign,
    ) => db.rawQuery(
      '''SELECT s.id, s.nome,
        CASE WHEN l.ativo=1 THEN 1 ELSE 0 END selecionado
        FROM $source s LEFT JOIN $link l
          ON l.$foreign=s.id AND l.modalidade_id=? AND l.comercio_id=s.comercio_id
        WHERE s.comercio_id=? AND s.ativo=1 ORDER BY s.nome COLLATE NOCASE''',
      [modalidadeId, comercioId],
    );
    return {
      'servicos': await load('servicos', 'modalidade_servicos', 'servico_id'),
      'profissionais': await load(
        'profissionais',
        'modalidade_profissionais',
        'profissional_id',
      ),
      'estoque': await load('estoque', 'modalidade_estoque', 'estoque_id'),
      'funcoes': await load(
        'funcoes_profissionais',
        'modalidade_funcoes',
        'funcao_id',
      ),
    };
  }

  Future<void> salvarVinculos(
    String modalidadeId, {
    required Set<String> servicos,
    required Set<String> profissionais,
    required Set<String> estoque,
    Set<String> funcoes = const {},
  }) async {
    _authorize();
    final db = await _databaseProvider();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((tx) async {
      Future<void> save(
        String table,
        String field,
        Set<String> selected,
      ) async {
        await tx.update(
          table,
          {'ativo': 0, 'atualizado_em': now},
          where: 'comercio_id=? AND modalidade_id=?',
          whereArgs: [comercioId, modalidadeId],
        );
        for (final id in selected) {
          await tx.insert(table, {
            'comercio_id': comercioId,
            'modalidade_id': modalidadeId,
            field: id,
            'ativo': 1,
            'atualizado_em': now,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      await save('modalidade_servicos', 'servico_id', servicos);
      await save('modalidade_profissionais', 'profissional_id', profissionais);
      await save('modalidade_estoque', 'estoque_id', estoque);
      await save('modalidade_funcoes', 'funcao_id', funcoes);
      await _sync(tx, modalidadeId, 'link', {
        'servicos': servicos.toList(),
        'profissionais': profissionais.toList(),
        'estoque': estoque.toList(),
        'funcoes': funcoes.toList(),
      });
      await _audit(tx, 'editar_vinculos', modalidadeId);
    });
  }

  Future<void> _link(
    String table,
    String modalidadeId,
    String field,
    String value,
  ) async {
    _authorize();
    final db = await _databaseProvider();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((tx) async {
      await tx.insert(table, {
        'comercio_id': comercioId,
        'modalidade_id': modalidadeId,
        field: value,
        'ativo': 1,
        'atualizado_em': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _sync(tx, modalidadeId, 'link', {'tabela': table, field: value});
    });
  }

  Future<int> _count(DatabaseExecutor db, String table, String id) async =>
      Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM $table WHERE comercio_id=? AND modalidade_id=?',
          [comercioId, id],
        ),
      ) ??
      0;

  Future<void> _sync(
    DatabaseExecutor tx,
    String id,
    String operation,
    Map<String, Object?> payload,
  ) {
    final now = DateTime.now().toUtc().toIso8601String();
    return tx.insert('fila_sincronizacao', {
      'id': 'sync_${IdGenerator.temporal()}',
      'comercio_id': comercioId,
      'unidade_id': SessionController.instance.unidadeAtiva,
      'entidade': 'modalidade',
      'entidade_id': id,
      'operacao': operation,
      'payload_json': jsonEncode(payload),
      'status': 'pendente',
      'criada_em': now,
      'atualizada_em': now,
    });
  }

  Future<void> _audit(DatabaseExecutor tx, String action, String id) =>
      tx.insert('ia_auditoria', {
        'id': IdGenerator.temporal(),
        'comercio_id': comercioId,
        'usuario_id': usuarioId,
        'unidade_id': SessionController.instance.unidadeAtiva,
        'intencao': 'gerenciar_modalidade',
        'acao': action,
        'confirmado': 1,
        'resultado': id,
        'criado_em': DateTime.now().toUtc().toIso8601String(),
      });

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp('[áàãâ]'), 'a')
      .replaceAll(RegExp('[éê]'), 'e')
      .replaceAll('í', 'i')
      .replaceAll(RegExp('[óõô]'), 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}
