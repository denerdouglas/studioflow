import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../services/session_controller.dart';

class ProfissionalBasicoRegistro {
  final String id;
  final String nome;
  final String whatsapp;
  final String cargo;
  final double percentualComissao;
  final bool ativo;

  const ProfissionalBasicoRegistro({
    required this.id,
    required this.nome,
    required this.whatsapp,
    required this.cargo,
    required this.percentualComissao,
    required this.ativo,
  });

  factory ProfissionalBasicoRegistro.doMapa(Map<String, Object?> mapa) {
    return ProfissionalBasicoRegistro(
      id: mapa['id'] as String,
      nome: mapa['nome'] as String,
      whatsapp: mapa['whatsapp'] as String? ?? '',
      cargo: mapa['cargo'] as String? ?? 'Profissional',
      percentualComissao: (mapa['percentual_comissao'] as num? ?? 50)
          .toDouble(),
      ativo: (mapa['ativo'] as int? ?? 1) == 1,
    );
  }
}

class ServicoBasicoRegistro {
  final String id;
  final String nome;
  final String categoria;
  final double preco;
  final int duracaoMinutos;
  final bool ativo;

  const ServicoBasicoRegistro({
    required this.id,
    required this.nome,
    required this.categoria,
    required this.preco,
    required this.duracaoMinutos,
    required this.ativo,
  });

  factory ServicoBasicoRegistro.doMapa(Map<String, Object?> mapa) {
    return ServicoBasicoRegistro(
      id: mapa['id'] as String,
      nome: mapa['nome'] as String,
      categoria: mapa['categoria'] as String? ?? 'Beleza',
      preco: (mapa['preco'] as num? ?? 0).toDouble(),
      duracaoMinutos: (mapa['duracao_minutos'] as num? ?? 60).toInt(),
      ativo: (mapa['ativo'] as int? ?? 1) == 1,
    );
  }
}

class CadastrosBasicosRepository {
  final DatabaseService _databaseService;

  CadastrosBasicosRepository({DatabaseService? databaseService})
    : _databaseService = databaseService ?? DatabaseService.instance;

  String get _comercioId => SessionController.instance.usuario!.comercioId;

  Future<void> garantirDadosIniciais() async {
    final Database db = await _databaseService.database;

    final profissionais = await db.query(
      'profissionais',
      columns: ['id'],
      where: 'comercio_id = ?',
      whereArgs: [_comercioId],
      limit: 1,
    );

    if (profissionais.isEmpty) {
      final agora = DateTime.now().toIso8601String();

      await db.insert('profissionais', {
        'id': '${_comercioId}_profissional_rafa',
        'nome': 'Rafa',
        'whatsapp': '',
        'cargo': 'Manicure',
        'ativo': 1,
        'percentual_comissao': 50,
        'meta_mensal': 7000,
        'faturamento_mes': 0,
        'data_cadastro': agora,
        'comercio_id': _comercioId,
      });

      await db.insert('profissionais', {
        'id': '${_comercioId}_profissional_ana',
        'nome': 'Ana',
        'whatsapp': '',
        'cargo': 'Profissional',
        'ativo': 1,
        'percentual_comissao': 50,
        'meta_mensal': 5000,
        'faturamento_mes': 0,
        'data_cadastro': agora,
        'comercio_id': _comercioId,
      });
    }

    final servicos = await db.query(
      'servicos',
      columns: ['id'],
      where: 'comercio_id = ?',
      whereArgs: [_comercioId],
      limit: 1,
    );

    if (servicos.isEmpty) {
      final agora = DateTime.now().toIso8601String();

      await db.insert('servicos', {
        'id': '${_comercioId}_servico_mao',
        'nome': 'Mão',
        'categoria': 'Manicure',
        'descricao': '',
        'preco': 40,
        'duracao_minutos': 60,
        'ativo': 1,
        'custo_estimado': 0,
        'data_cadastro': agora,
        'comercio_id': _comercioId,
      });

      await db.insert('servicos', {
        'id': '${_comercioId}_servico_pe',
        'nome': 'Pé',
        'categoria': 'Manicure',
        'descricao': '',
        'preco': 40,
        'duracao_minutos': 60,
        'ativo': 1,
        'custo_estimado': 0,
        'data_cadastro': agora,
        'comercio_id': _comercioId,
      });

      await db.insert('servicos', {
        'id': '${_comercioId}_servico_pe_mao',
        'nome': 'Pé e mão',
        'categoria': 'Manicure',
        'descricao': '',
        'preco': 80,
        'duracao_minutos': 120,
        'ativo': 1,
        'custo_estimado': 0,
        'data_cadastro': agora,
        'comercio_id': _comercioId,
      });
    }
  }

  Future<List<ProfissionalBasicoRegistro>> listarProfissionais() async {
    final Database db = await _databaseService.database;

    final registros = await db.query(
      'profissionais',
      where: 'ativo = ? AND comercio_id = ?',
      whereArgs: [1, _comercioId],
      orderBy: 'nome COLLATE NOCASE ASC',
    );

    return registros.map(ProfissionalBasicoRegistro.doMapa).toList();
  }

  Future<List<ServicoBasicoRegistro>> listarServicos() async {
    final Database db = await _databaseService.database;

    final registros = await db.query(
      'servicos',
      where: 'ativo = ? AND comercio_id = ?',
      whereArgs: [1, _comercioId],
      orderBy: 'nome COLLATE NOCASE ASC',
    );

    return registros.map(ServicoBasicoRegistro.doMapa).toList();
  }

  Future<ProfissionalBasicoRegistro?> buscarProfissionalPorId(
    String profissionalId,
  ) async {
    final Database db = await _databaseService.database;

    final registros = await db.query(
      'profissionais',
      where: 'id = ? AND ativo = ? AND comercio_id = ?',
      whereArgs: [profissionalId, 1, _comercioId],
      limit: 1,
    );

    if (registros.isEmpty) {
      return null;
    }

    return ProfissionalBasicoRegistro.doMapa(registros.first);
  }

  Future<ServicoBasicoRegistro?> buscarServicoPorId(String servicoId) async {
    final Database db = await _databaseService.database;

    final registros = await db.query(
      'servicos',
      where: 'id = ? AND ativo = ? AND comercio_id = ?',
      whereArgs: [servicoId, 1, _comercioId],
      limit: 1,
    );

    if (registros.isEmpty) {
      return null;
    }

    return ServicoBasicoRegistro.doMapa(registros.first);
  }
}
