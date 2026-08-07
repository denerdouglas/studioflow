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
    // Hardcodes globais removidos.
    // A inicialização de novas contas será feita através da seleção
    // de segmento/modalidade (SegmentoTemplatesRepository).
    // O sistema manterá as contas existentes intactas pois a lógica
    // não apaga registros de profissionais/serviços existentes.
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
