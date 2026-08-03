import '../database/database_service.dart';
import '../models/domain/unidade.dart';
import '../services/session_controller.dart';

class UnidadesRepository {
  final DatabaseService _databaseService;

  UnidadesRepository({DatabaseService? databaseService})
    : _databaseService = databaseService ?? DatabaseService.instance;

  String get _comercioId => SessionController.instance.usuario!.comercioId;

  Future<List<Unidade>> listar({bool incluirInativas = true}) async {
    final db = await _databaseService.database;

    final resultado = await db.query(
      'unidades',
      where: incluirInativas
          ? 'comercio_id = ?'
          : 'comercio_id = ? AND ativo = ?',
      whereArgs: incluirInativas ? [_comercioId] : [_comercioId, 1],
      orderBy: 'principal DESC, nome COLLATE NOCASE ASC',
    );

    return resultado.map(Unidade.doMapa).toList();
  }

  Future<Unidade?> buscarPorId(String id) async {
    final db = await _databaseService.database;
    final resultado = await db.query(
      'unidades',
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [id, _comercioId],
      limit: 1,
    );

    if (resultado.isEmpty) return null;
    return Unidade.doMapa(resultado.first);
  }

  Future<void> inserir(Unidade unidade) async {
    final db = await _databaseService.database;

    await db.transaction((txn) async {
      if (unidade.principal) {
        await txn.update(
          'unidades',
          {'principal': 0},
          where: 'comercio_id = ?',
          whereArgs: [_comercioId],
        );
      }

      await txn.insert('unidades', {
        ...unidade.paraMapa(),
        'comercio_id': _comercioId,
        'criado_em': DateTime.now().toUtc().toIso8601String(),
        'atualizado_em': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  Future<void> atualizar(Unidade unidade) async {
    final db = await _databaseService.database;

    await db.transaction((txn) async {
      if (unidade.principal) {
        await txn.update(
          'unidades',
          {'principal': 0},
          where: 'comercio_id = ?',
          whereArgs: [_comercioId],
        );
      }

      await txn.update(
        'unidades',
        {
          ...unidade.paraMapa(),
          'atualizado_em': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ? AND comercio_id = ?',
        whereArgs: [unidade.id, _comercioId],
      );
    });
  }

  Future<void> salvar(Unidade unidade) async {
    final existente = await buscarPorId(unidade.id);
    if (existente == null) {
      await inserir(unidade);
    } else {
      await atualizar(unidade);
    }
  }

  Future<void> excluir(String id) async {
    final db = await _databaseService.database;
    await db.delete(
      'unidades',
      where: 'id = ? AND comercio_id = ? AND principal = 0',
      whereArgs: [id, _comercioId],
    );
  }
}
