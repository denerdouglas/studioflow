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
  final String? unidadeId;
  final String? corIdentificacao;
  final double? comissaoPercentual;
  final List<String> profissionaisAutorizados;

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
    this.unidadeId,
    this.corIdentificacao,
    this.comissaoPercentual,
    this.profissionaisAutorizados = const [],
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
      'unidade_id': unidadeId,
      'cor_identificacao': corIdentificacao,
      'comissao_percentual': comissaoPercentual,
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
      unidadeId: mapa['unidade_id'] as String?,
      corIdentificacao: mapa['cor_identificacao'] as String?,
      comissaoPercentual: mapa['comissao_percentual'] != null
          ? (mapa['comissao_percentual'] as num).toDouble()
          : null,
      profissionaisAutorizados: _parseProfissionais(
        mapa['profissionais_autorizados'],
      ),
    );
  }

  static List<String> _parseProfissionais(dynamic dado) {
    if (dado == null) return const [];
    if (dado is String) {
      return dado.split(',').where((e) => e.isNotEmpty).toList();
    }
    if (dado is List) return List<String>.from(dado);
    return const [];
  }

  ServicoRegistro copiarCom({
    String? nome,
    String? categoria,
    String? descricao,
    double? preco,
    int? duracaoMinutos,
    bool? ativo,
    double? custoEstimado,
    String? unidadeId,
    String? corIdentificacao,
    double? comissaoPercentual,
    List<String>? profissionaisAutorizados,
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
      unidadeId: unidadeId ?? this.unidadeId,
      corIdentificacao: corIdentificacao ?? this.corIdentificacao,
      comissaoPercentual: comissaoPercentual ?? this.comissaoPercentual,
      profissionaisAutorizados:
          profissionaisAutorizados ?? this.profissionaisAutorizados,
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

    final baseQuery = '''
      SELECT s.*, GROUP_CONCAT(ps.profissional_id) as profissionais_autorizados
      FROM servicos s
      LEFT JOIN profissional_servicos ps ON ps.servico_id = s.id
      WHERE s.comercio_id = ?
    ''';

    final query = incluirInativos
        ? '$baseQuery GROUP BY s.id ORDER BY s.nome COLLATE NOCASE ASC'
        : '$baseQuery AND s.ativo = 1 GROUP BY s.id ORDER BY s.nome COLLATE NOCASE ASC';

    final resultado = await db.rawQuery(query, [_comercioId]);

    return resultado.map(ServicoRegistro.doMapa).toList();
  }

  Future<List<ServicoRegistro>> pesquisar(
    String texto, {
    bool incluirInativos = true,
  }) async {
    final Database db = await _databaseService.database;

    final termo = '%${texto.toLowerCase()}%';

    final baseQuery = '''
      SELECT s.*, GROUP_CONCAT(ps.profissional_id) as profissionais_autorizados
      FROM servicos s
      LEFT JOIN profissional_servicos ps ON ps.servico_id = s.id
      WHERE s.comercio_id = ? AND LOWER(s.nome) LIKE ?
    ''';

    final query = incluirInativos
        ? '$baseQuery GROUP BY s.id ORDER BY s.nome COLLATE NOCASE ASC'
        : '$baseQuery AND s.ativo = 1 GROUP BY s.id ORDER BY s.nome COLLATE NOCASE ASC';

    final resultado = await db.rawQuery(query, [_comercioId, termo]);

    return resultado.map(ServicoRegistro.doMapa).toList();
  }

  Future<ServicoRegistro?> buscarPorId(String id) async {
    final Database db = await _databaseService.database;

    final query = '''
      SELECT s.*, GROUP_CONCAT(ps.profissional_id) as profissionais_autorizados
      FROM servicos s
      LEFT JOIN profissional_servicos ps ON ps.servico_id = s.id
      WHERE s.id = ? AND s.comercio_id = ?
      GROUP BY s.id
      LIMIT 1
    ''';

    final resultado = await db.rawQuery(query, [id, _comercioId]);

    if (resultado.isEmpty) {
      return null;
    }

    return ServicoRegistro.doMapa(resultado.first);
  }

  Future<void> inserir(ServicoRegistro servico) async {
    final Database db = await _databaseService.database;

    await db.transaction((txn) async {
      await txn.insert('servicos', {
        ...servico.paraMapa(),
        'comercio_id': _comercioId,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      for (final profissionalId in servico.profissionaisAutorizados) {
        await txn.insert('profissional_servicos', {
          'profissional_id': profissionalId,
          'servico_id': servico.id,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> atualizar(ServicoRegistro servico) async {
    final Database db = await _databaseService.database;

    await db.transaction((txn) async {
      final quantidadeAlterada = await txn.update(
        'servicos',
        servico.paraMapa(),
        where: 'id = ? AND comercio_id = ?',
        whereArgs: [servico.id, _comercioId],
      );

      if (quantidadeAlterada == 0) {
        throw StateError('Serviço não encontrado.');
      }

      await txn.delete(
        'profissional_servicos',
        where: 'servico_id = ?',
        whereArgs: [servico.id],
      );

      for (final profissionalId in servico.profissionaisAutorizados) {
        await txn.insert('profissional_servicos', {
          'profissional_id': profissionalId,
          'servico_id': servico.id,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
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
