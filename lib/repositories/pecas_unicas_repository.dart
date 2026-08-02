import 'package:sqflite/sqflite.dart';
import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../services/session_controller.dart';
import '../models/domain/acesso.dart';

class PecasUnicasRepository {
  final Future<Database> Function() _databaseProvider;

  PecasUnicasRepository({Future<Database> Function()? databaseProvider})
      : _databaseProvider = databaseProvider ?? (() => DatabaseService.instance.database);

  UsuarioAcesso get _usuario {
    final u = SessionController.instance.usuario;
    if (u == null) throw StateError('Usuário não autenticado.');
    return u;
  }

  Future<String> cadastrar({
    required String codigoExclusivo,
    required String nome,
    String? descricao,
    String? material,
    String? marca,
    String? fornecedorId,
    required double custo,
    required double preco,
  }) async {
    final db = await _databaseProvider();
    final u = _usuario;
    
    final existente = await db.query(
      'pecas_unicas',
      where: 'comercio_id = ? AND codigo_exclusivo = ?',
      whereArgs: [u.comercioId, codigoExclusivo],
      limit: 1,
    );
    if (existente.isNotEmpty) {
      throw StateError('Peça única com este código exclusivo já existe.');
    }

    final id = 'peca_${IdGenerator.temporal()}';
    await db.insert('pecas_unicas', {
      'id': id,
      'comercio_id': u.comercioId,
      'codigo_exclusivo': codigoExclusivo,
      'nome': nome,
      'descricao': descricao,
      'material': material,
      'marca': marca,
      'fornecedor_id': fornecedorId,
      'custo': custo,
      'preco': preco,
      'status': 'disponivel',
      'data_cadastro': DateTime.now().toIso8601String(),
    });
    return id;
  }

  Future<void> reservar(String id, String clienteId) async {
    final db = await _databaseProvider();
    final u = _usuario;
    final changed = await db.update(
      'pecas_unicas',
      {'status': 'reservada', 'cliente_id': clienteId},
      where: 'id = ? AND comercio_id = ? AND status = ?',
      whereArgs: [id, u.comercioId, 'disponivel'],
    );
    if (changed == 0) throw StateError('Peça não disponível para reserva.');
  }

  Future<void> devolver(String id) async {
    final db = await _databaseProvider();
    final u = _usuario;
    final changed = await db.update(
      'pecas_unicas',
      {'status': 'disponivel', 'cliente_id': null},
      where: 'id = ? AND comercio_id = ? AND status IN (?, ?)',
      whereArgs: [id, u.comercioId, 'reservada', 'vendida'],
    );
    if (changed == 0) throw StateError('Peça não pode ser devolvida.');
  }

  Future<void> vender(String id, String profissionalId, double comissao) async {
    final db = await _databaseProvider();
    final u = _usuario;
    final changed = await db.update(
      'pecas_unicas',
      {
        'status': 'vendida',
        'profissional_vendedor_id': profissionalId,
        'comissao': comissao,
        'data_venda': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND comercio_id = ? AND status IN (?, ?)',
      whereArgs: [id, u.comercioId, 'disponivel', 'reservada'],
    );
    if (changed == 0) throw StateError('Peça já vendida ou indisponível.');
  }

  Future<Map<String, Object?>?> buscar(String codigoExclusivo) async {
    final db = await _databaseProvider();
    final u = _usuario;
    final rows = await db.query(
      'pecas_unicas',
      where: 'comercio_id = ? AND codigo_exclusivo = ?',
      whereArgs: [u.comercioId, codigoExclusivo],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> buscarPorId(String id) async {
    final db = await _databaseProvider();
    final u = _usuario;
    final rows = await db.query(
      'pecas_unicas',
      where: 'comercio_id = ? AND id = ?',
      whereArgs: [u.comercioId, id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> listarDisponiveis() async {
    final db = await _databaseProvider();
    final u = _usuario;
    return db.query(
      'pecas_unicas',
      where: 'comercio_id = ? AND status = ?',
      whereArgs: [u.comercioId, 'disponivel'],
    );
  }
}
