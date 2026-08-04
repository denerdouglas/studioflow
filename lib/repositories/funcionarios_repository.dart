import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../models/domain/acesso.dart';
import '../services/session_controller.dart';

class ProfissionalRegistro {
  final String id;
  final String nome;
  final String whatsapp;
  final String email;
  final String cargo;
  final String fotoPerfil;
  final bool ativo;
  final double percentualComissao;
  final double metaMensal;
  final double faturamentoMes;
  final DateTime dataCadastro;
  final String? documento;
  final String? rg;
  final String? dataNascimento;
  final String? chavePix;
  final String? banco;
  final String? corAgenda;
  final String? unidadeId;
  final String? sexo;
  final String? observacoes;
  final String? contatoEmergencia;
  final List<String> funcoes;

  const ProfissionalRegistro({
    required this.id,
    required this.nome,
    required this.whatsapp,
    required this.email,
    required this.cargo,
    required this.fotoPerfil,
    required this.ativo,
    required this.percentualComissao,
    required this.metaMensal,
    required this.faturamentoMes,
    required this.dataCadastro,
    this.documento,
    this.rg,
    this.dataNascimento,
    this.chavePix,
    this.banco,
    this.corAgenda,
    this.unidadeId,
    this.sexo,
    this.observacoes,
    this.contatoEmergencia,
    this.funcoes = const [],
  });

  Map<String, Object?> paraMapa() {
    return {
      'id': id,
      'nome': nome,
      'whatsapp': whatsapp,
      'email': email,
      'cargo': cargo,
      'foto_perfil': fotoPerfil,
      'ativo': ativo ? 1 : 0,
      'percentual_comissao': percentualComissao,
      'meta_mensal': metaMensal,
      'faturamento_mes': faturamentoMes,
      'data_cadastro': dataCadastro.toIso8601String(),
      'documento': documento,
      'rg': rg,
      'data_nascimento': dataNascimento,
      'chave_pix': chavePix,
      'banco': banco,
      'cor_agenda': corAgenda,
      'unidade_id': unidadeId,
      'sexo': sexo,
      'observacoes': observacoes,
      'contato_emergencia': contatoEmergencia,
    };
  }

  factory ProfissionalRegistro.doMapa(Map<String, Object?> mapa) {
    return ProfissionalRegistro(
      id: mapa['id'] as String,
      nome: mapa['nome'] as String? ?? '',
      whatsapp: mapa['whatsapp'] as String? ?? '',
      email: mapa['email'] as String? ?? '',
      cargo: mapa['cargo'] as String? ?? 'Profissional',
      fotoPerfil: mapa['foto_perfil'] as String? ?? '',
      ativo: (mapa['ativo'] as num? ?? 1) == 1,
      percentualComissao: (mapa['percentual_comissao'] as num? ?? 50)
          .toDouble(),
      metaMensal: (mapa['meta_mensal'] as num? ?? 0).toDouble(),
      faturamentoMes: (mapa['faturamento_mes'] as num? ?? 0).toDouble(),
      dataCadastro:
          DateTime.tryParse(mapa['data_cadastro'] as String? ?? '') ??
          DateTime.now(),
      documento: mapa['documento'] as String?,
      rg: mapa['rg'] as String?,
      dataNascimento: mapa['data_nascimento'] as String?,
      chavePix: mapa['chave_pix'] as String?,
      banco: mapa['banco'] as String?,
      corAgenda: mapa['cor_agenda'] as String?,
      unidadeId: mapa['unidade_id'] as String?,
      sexo: mapa['sexo'] as String?,
      observacoes: mapa['observacoes'] as String?,
      contatoEmergencia: mapa['contato_emergencia'] as String?,
      funcoes: (mapa['funcoes'] as List?)?.cast<String>() ?? const [],
    );
  }

  ProfissionalRegistro copiarCom({
    String? nome,
    String? whatsapp,
    String? email,
    String? cargo,
    String? fotoPerfil,
    bool? ativo,
    double? percentualComissao,
    double? metaMensal,
    double? faturamentoMes,
    String? documento,
    String? rg,
    String? dataNascimento,
    String? chavePix,
    String? banco,
    String? corAgenda,
    String? unidadeId,
    String? sexo,
    String? observacoes,
    String? contatoEmergencia,
    List<String>? funcoes,
  }) {
    return ProfissionalRegistro(
      id: id,
      nome: nome ?? this.nome,
      whatsapp: whatsapp ?? this.whatsapp,
      email: email ?? this.email,
      cargo: cargo ?? this.cargo,
      fotoPerfil: fotoPerfil ?? this.fotoPerfil,
      ativo: ativo ?? this.ativo,
      percentualComissao: percentualComissao ?? this.percentualComissao,
      metaMensal: metaMensal ?? this.metaMensal,
      faturamentoMes: faturamentoMes ?? this.faturamentoMes,
      dataCadastro: dataCadastro,
      documento: documento ?? this.documento,
      rg: rg ?? this.rg,
      dataNascimento: dataNascimento ?? this.dataNascimento,
      chavePix: chavePix ?? this.chavePix,
      banco: banco ?? this.banco,
      corAgenda: corAgenda ?? this.corAgenda,
      unidadeId: unidadeId ?? this.unidadeId,
      sexo: sexo ?? this.sexo,
      observacoes: observacoes ?? this.observacoes,
      contatoEmergencia: contatoEmergencia ?? this.contatoEmergencia,
      funcoes: funcoes ?? this.funcoes,
    );
  }
}

class FuncionariosRepository {
  final DatabaseService _databaseService;

  FuncionariosRepository({DatabaseService? databaseService})
    : _databaseService = databaseService ?? DatabaseService.instance;

  String get _comercioId => SessionController.instance.usuario!.comercioId;

  Future<List<ProfissionalRegistro>> listar({
    bool incluirInativos = true,
  }) async {
    final Database db = await _databaseService.database;

    final resultado = await db.query(
      'profissionais',
      where: incluirInativos
          ? 'comercio_id = ?'
          : 'ativo = ? AND comercio_id = ?',
      whereArgs: incluirInativos ? [_comercioId] : [1, _comercioId],
      orderBy: 'nome COLLATE NOCASE ASC',
    );

    return resultado.map(ProfissionalRegistro.doMapa).toList();
  }

  Future<ProfissionalRegistro?> buscarPorId(String id) async {
    final Database db = await _databaseService.database;

    final resultado = await db.query(
      'profissionais',
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [id, _comercioId],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return ProfissionalRegistro.doMapa(resultado.first);
  }

  Future<void> inserir(ProfissionalRegistro profissional) async {
    final Database db = await _databaseService.database;

    await db.insert('profissionais', {
      ...profissional.paraMapa(),
      'comercio_id': _comercioId,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<void> atualizar(ProfissionalRegistro profissional) async {
    final Database db = await _databaseService.database;

    final alterados = await db.update(
      'profissionais',
      profissional.paraMapa(),
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [profissional.id, _comercioId],
    );

    if (alterados == 0) {
      throw StateError('Funcionário não encontrado.');
    }
  }

  Future<void> salvar(ProfissionalRegistro profissional) async {
    final existente = await buscarPorId(profissional.id);
    if (existente == null) {
      await inserir(profissional);
    } else {
      await atualizar(profissional);
    }
    if (profissional.funcoes.isNotEmpty) {
      await salvarFuncoes(profissional.id, profissional.funcoes);
    }
  }

  Future<List<String>> listarFuncoes(String profissionalId) async {
    final db = await _databaseService.database;
    final rows = await db.rawQuery(
      '''SELECT f.nome FROM funcoes_profissionais f
      JOIN profissional_funcoes pf ON pf.funcao_id=f.id AND pf.comercio_id=f.comercio_id
      WHERE pf.comercio_id=? AND pf.profissional_id=? AND pf.ativo=1 AND f.ativo=1
      ORDER BY f.nome COLLATE NOCASE''',
      [_comercioId, profissionalId],
    );
    return rows.map((e) => e['nome'] as String).toList();
  }

  Future<List<String>> listarFuncoesDisponiveis() async {
    final db = await _databaseService.database;
    final rows = await db.query(
      'funcoes_profissionais',
      columns: ['nome'],
      where: 'comercio_id=? AND ativo=1',
      whereArgs: [_comercioId],
      orderBy: 'nome COLLATE NOCASE',
    );
    return rows.map((e) => e['nome'] as String).toList();
  }

  Future<void> salvarFuncoes(
    String profissionalId,
    Iterable<String> values,
  ) async {
    final user = SessionController.instance.usuario;
    if (user == null || !user.pode(ModuloPermissao.funcionarios)) {
      throw StateError('Ação não autorizada para colaboradores.');
    }
    final unique = <String, String>{};
    for (final value in values) {
      final name = value.trim();
      if (name.isNotEmpty) {
        unique[name.toLowerCase()] = name;
      }
    }
    if (unique.isEmpty) {
      throw StateError('Selecione ao menos uma função.');
    }
    final db = await _databaseService.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((tx) async {
      await tx.update(
        'profissional_funcoes',
        {'ativo': 0, 'atualizado_em': now},
        where: 'comercio_id=? AND profissional_id=?',
        whereArgs: [_comercioId, profissionalId],
      );
      for (final name in unique.values) {
        final normalized = name
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
            .replaceAll(RegExp(r'^_|_$'), '');
        final rows = await tx.query(
          'funcoes_profissionais',
          columns: ['id'],
          where: 'comercio_id=? AND nome_normalizado=?',
          whereArgs: [_comercioId, normalized],
          limit: 1,
        );
        final functionId = rows.isEmpty
            ? 'func_${_comercioId}_${DateTime.now().microsecondsSinceEpoch}_$normalized'
            : rows.single['id'] as String;
        if (rows.isEmpty) {
          await tx.insert('funcoes_profissionais', {
            'id': functionId,
            'comercio_id': _comercioId,
            'nome': name,
            'nome_normalizado': normalized,
            'personalizada': 1,
            'ativo': 1,
            'criado_em': now,
            'atualizado_em': now,
          });
        }
        await tx.insert('profissional_funcoes', {
          'comercio_id': _comercioId,
          'profissional_id': profissionalId,
          'funcao_id': functionId,
          'ativo': 1,
          'atualizado_em': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await tx.insert('fila_sincronizacao', {
        'id': 'sync_${DateTime.now().microsecondsSinceEpoch}',
        'comercio_id': _comercioId,
        'unidade_id': SessionController.instance.unidadeAtiva,
        'entidade': 'profissional_funcoes',
        'entidade_id': profissionalId,
        'operacao': 'upsert',
        'payload_json': jsonEncode(unique.values.toList()),
        'status': 'pendente',
        'criada_em': now,
        'atualizada_em': now,
      });
    });
  }

  Future<void> alterarStatus({required String id, required bool ativo}) async {
    final Database db = await _databaseService.database;

    await db.update(
      'profissionais',
      {'ativo': ativo ? 1 : 0},
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [id, _comercioId],
    );
  }

  Future<bool> excluirSeSemHistorico(String id) async {
    final db = await _databaseService.database;
    return db.transaction((tx) async {
      final usos = await tx.rawQuery(
        '''SELECT
          (SELECT COUNT(*) FROM agendamentos
            WHERE comercio_id=? AND profissional_id=?) +
          (SELECT COUNT(*) FROM comissoes
            WHERE comercio_id=? AND profissional_id=?) +
          (SELECT COUNT(*) FROM pacote_vendas
            WHERE comercio_id=? AND vendedor_profissional_id=?) AS total''',
        [_comercioId, id, _comercioId, id, _comercioId, id],
      );
      if ((usos.single['total'] as num? ?? 0) > 0) return false;
      await tx.delete(
        'profissional_funcoes',
        where: 'comercio_id=? AND profissional_id=?',
        whereArgs: [_comercioId, id],
      );
      await tx.delete(
        'profissional_servicos',
        where: 'profissional_id=?',
        whereArgs: [id],
      );
      return await tx.delete(
            'profissionais',
            where: 'id=? AND comercio_id=?',
            whereArgs: [id, _comercioId],
          ) >
          0;
    });
  }

  Future<bool> existeNome({required String nome, String? ignorarId}) async {
    final Database db = await _databaseService.database;

    String where = 'comercio_id = ? AND LOWER(TRIM(nome)) = LOWER(TRIM(?))';

    final argumentos = <Object?>[_comercioId, nome];

    if (ignorarId != null) {
      where += ' AND id != ?';
      argumentos.add(ignorarId);
    }

    final resultado = await db.query(
      'profissionais',
      columns: ['id'],
      where: where,
      whereArgs: argumentos,
      limit: 1,
    );

    return resultado.isNotEmpty;
  }

  Future<int> quantidade({bool somenteAtivos = false}) async {
    final Database db = await _databaseService.database;

    final resultado = await db.rawQuery(
      somenteAtivos
          ? '''
            SELECT COUNT(*) AS total
            FROM profissionais
            WHERE ativo = 1 AND comercio_id = ?
            '''
          : '''
            SELECT COUNT(*) AS total
            FROM profissionais WHERE comercio_id = ?
            ''',
      [_comercioId],
    );

    return (resultado.first['total'] as num? ?? 0).toInt();
  }

  Future<double> totalFaturamentoMes() async {
    final Database db = await _databaseService.database;

    final resultado = await db.rawQuery(
      '''
      SELECT SUM(faturamento_mes) AS total
      FROM profissionais
      WHERE ativo = 1 AND comercio_id = ?
      ''',
      [_comercioId],
    );

    return (resultado.first['total'] as num? ?? 0).toDouble();
  }

  Future<double> totalMetasMes() async {
    final Database db = await _databaseService.database;

    final resultado = await db.rawQuery(
      '''
      SELECT SUM(meta_mensal) AS total
      FROM profissionais
      WHERE ativo = 1 AND comercio_id = ?
      ''',
      [_comercioId],
    );

    return (resultado.first['total'] as num? ?? 0).toDouble();
  }

  Future<List<ProfissionalRegistro>> pesquisar(
    String texto, {
    bool incluirInativos = true,
  }) async {
    final Database db = await _databaseService.database;

    final pesquisa = '%${texto.trim()}%';

    String where = '''
      comercio_id = ? AND (
        nome LIKE ?
        OR cargo LIKE ?
        OR whatsapp LIKE ?
        OR email LIKE ?
      )
    ''';

    final argumentos = <Object?>[
      _comercioId,
      pesquisa,
      pesquisa,
      pesquisa,
      pesquisa,
    ];

    if (!incluirInativos) {
      where += ' AND ativo = ?';
      argumentos.add(1);
    }

    final resultado = await db.query(
      'profissionais',
      where: where,
      whereArgs: argumentos,
      orderBy: 'nome COLLATE NOCASE ASC',
    );

    return resultado.map(ProfissionalRegistro.doMapa).toList();
  }
}
