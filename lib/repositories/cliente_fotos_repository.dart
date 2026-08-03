import 'package:sqflite/sqflite.dart';
import '../database/database_service.dart';
import '../services/session_controller.dart';
import '../models/domain/cliente.dart';

class ClienteFotosRepository {
  final DatabaseService _databaseService;

  ClienteFotosRepository({DatabaseService? databaseService})
    : _databaseService = databaseService ?? DatabaseService.instance;

  String get _comercioId => SessionController.instance.usuario!.comercioId;

  Future<List<FotoCliente>> listarPorCliente(String clienteId) async {
    final db = await _databaseService.database;
    final registros = await db.query(
      'fotos_cliente',
      where: 'cliente_id = ? AND comercio_id = ? AND excluido_em IS NULL',
      whereArgs: [clienteId, _comercioId],
      orderBy: 'data_trabalho DESC, criado_em DESC',
    );

    return registros.map(FotoCliente.doMapa).toList();
  }

  Future<void> inserir(FotoCliente foto) async {
    final db = await _databaseService.database;
    await db.insert('fotos_cliente', {
      ...foto.paraMapa(),
      'comercio_id': _comercioId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> excluir(String fotoId) async {
    final db = await _databaseService.database;
    await db.update(
      'fotos_cliente',
      {
        'excluido_em': DateTime.now().toUtc().toIso8601String(),
        'atualizado_em': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [fotoId, _comercioId],
    );
  }
}
