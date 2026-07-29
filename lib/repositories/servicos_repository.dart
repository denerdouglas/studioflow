import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../services/session_controller.dart';

class ServicoRegistro {
  final String id;
  final String nome;
  final String categoria;
  final String descricao;
  final double preco;
  final int duracaoMinutos;
  final bool ativo;
  final double custoEstimado;
  final DateTime dataCadastro;

  const ServicoRegistro({
    required this.id,
    required this.nome,
    required this.categoria,
    required this.descricao,
    required this.preco,
    required this.duracaoMinutos,
    required this.ativo,
    required this.custoEstimado,
    required this.dataCadastro,
  });

  Map<String, Object?> paraMapa() {
    return {
      'id': id,
      'nome': nome,
      'categoria': categoria,
      'descricao': descricao,
      'preco': preco,
      'duracao_minutos': duracaoMinutos,
      'ativo': ativo ? 1 : 0,
      'custo_estimado': custoEstimado,
      'data_cadastro': dataCadastro.toIso8601String(),
    };
  }

  factory ServicoRegistro.doMapa(Map<String, Object?> mapa) {
    return ServicoRegistro(
      id: mapa['id'] as String,
      nome: mapa['nome'] as String? ?? 'Serviço',
      categoria: mapa['categoria'] as String? ?? 'Outros',
      descricao: mapa['descricao'] as String? ?? '',
      preco: (mapa['preco'] as num? ?? 0).toDouble(),
      duracaoMinutos: (mapa['duracao_minutos'] as num? ?? 60).toInt(),
      ativo: (mapa['ativo'] as num? ?? 1) == 1,
      custoEstimado: (mapa['custo_estimado'] as num? ?? 0).toDouble(),
      dataCadastro:
          DateTime.tryParse(mapa['data_cadastro'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  ServicoRegistro copiarCom({
    String? nome,
    String? categoria,
    String? descricao,
    double? preco,
    int? duracaoMinutos,
    bool? ativo,
    double? custoEstimado,
  }) {
    return ServicoRegistro(
      id: id,
      nome: nome ?? this.nome,
      categoria: categoria ?? this.categoria,
      descricao: descricao ?? this.descricao,
      preco: preco ?? this.preco,
      duracaoMinutos: duracaoMinutos ?? this.duracaoMinutos,
      ativo: ativo ?? this.ativo,
      custoEstimado: custoEstimado ?? this.custoEstimado,
      dataCadastro: dataCadastro,
    );
  }
}

class ServicosRepository {
  final DatabaseService _databaseService;

  ServicosRepository({DatabaseService? databaseService})
    : _databaseService = databaseService ?? DatabaseService.instance;

  String get _comercioId => SessionController.instance.usuario!.comercioId;

  Future<List<ServicoRegistro>> listar({bool incluirInativos = true}) async {
    final Database db = await _databaseService.database;

    final resultado = await db.query(
      'servicos',
      where: incluirInativos
          ? 'comercio_id = ?'
          : 'ativo = ? AND comercio_id = ?',
      whereArgs: incluirInativos ? [_comercioId] : [1, _comercioId],
      orderBy: 'nome COLLATE NOCASE ASC',
    );

    return resultado.map(ServicoRegistro.doMapa).toList();
  }

  Future<List<ServicoRegistro>> pesquisar(
    String texto, {
    bool incluirInativos = true,
  }) async {
    final Database db = await _databaseService.database;

    final pesquisa = '%${texto.trim()}%';

    String where = 'comercio_id = ? AND (nome LIKE ? OR categoria LIKE ?)';

    final argumentos = <Object?>[_comercioId, pesquisa, pesquisa];

    if (!incluirInativos) {
      where += ' AND ativo = ?';
      argumentos.add(1);
    }

    final resultado = await db.query(
      'servicos',
      where: where,
      whereArgs: argumentos,
      orderBy: 'nome COLLATE NOCASE ASC',
    );

    return resultado.map(ServicoRegistro.doMapa).toList();
  }

  Future<ServicoRegistro?> buscarPorId(String id) async {
    final Database db = await _databaseService.database;

    final resultado = await db.query(
      'servicos',
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [id, _comercioId],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return ServicoRegistro.doMapa(resultado.first);
  }

  Future<void> inserir(ServicoRegistro servico) async {
    final Database db = await _databaseService.database;

    await db.insert('servicos', {
      ...servico.paraMapa(),
      'comercio_id': _comercioId,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<void> atualizar(ServicoRegistro servico) async {
    final Database db = await _databaseService.database;

    final quantidadeAlterada = await db.update(
      'servicos',
      servico.paraMapa(),
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [servico.id, _comercioId],
    );

    if (quantidadeAlterada == 0) {
      throw StateError('Serviço não encontrado.');
    }
  }

  Future<void> excluir(String id) async {
    final Database db = await _databaseService.database;

    await db.update(
      'servicos',
      {'ativo': 0},
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [id, _comercioId],
    );
  }

  Future<void> alterarStatus({required String id, required bool ativo}) async {
    final Database db = await _databaseService.database;

    await db.update(
      'servicos',
      {'ativo': ativo ? 1 : 0},
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [id, _comercioId],
    );
  }

  Future<List<String>> listarCategorias() async {
    final Database db = await _databaseService.database;

    final resultado = await db.rawQuery(
      '''
      SELECT DISTINCT categoria
      FROM servicos
      WHERE categoria IS NOT NULL
        AND categoria != '' AND comercio_id = ?
      ORDER BY categoria COLLATE NOCASE ASC
      ''',
      [_comercioId],
    );

    return resultado
        .map((registro) => registro['categoria'] as String)
        .toList();
  }

  Future<int> quantidade({bool somenteAtivos = false}) async {
    final Database db = await _databaseService.database;

    final resultado = await db.rawQuery(
      somenteAtivos
          ? '''
            SELECT COUNT(*) AS total
            FROM servicos
            WHERE ativo = 1 AND comercio_id = ?
            '''
          : '''
            SELECT COUNT(*) AS total
            FROM servicos WHERE comercio_id = ?
            ''',
      [_comercioId],
    );

    return (resultado.first['total'] as num? ?? 0).toInt();
  }

  Future<double> valorMedio() async {
    final Database db = await _databaseService.database;

    final resultado = await db.rawQuery(
      '''
      SELECT AVG(preco) AS media
      FROM servicos
      WHERE ativo = 1 AND comercio_id = ?
      ''',
      [_comercioId],
    );

    final valor = resultado.first['media'];

    if (valor == null) {
      return 0;
    }

    return (valor as num).toDouble();
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
      'servicos',
      columns: ['id'],
      where: where,
      whereArgs: argumentos,
      limit: 1,
    );

    return resultado.isNotEmpty;
  }

  Future<void> salvar(ServicoRegistro servico) async {
    final nomeExiste = await existeNome(
      nome: servico.nome,
      ignorarId: servico.id,
    );

    if (nomeExiste) {
      throw StateError('Já existe um serviço com esse nome.');
    }

    final existente = await buscarPorId(servico.id);

    if (existente == null) {
      await inserir(servico);
      return;
    }

    await atualizar(servico);
  }

  Future<void> reativar(String id) async {
    await alterarStatus(id: id, ativo: true);
  }

  Future<List<ServicoRegistro>> listarAtivos() async {
    return listar(incluirInativos: false);
  }
}
