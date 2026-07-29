import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
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
      return;
    }

    await atualizar(profissional);
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
