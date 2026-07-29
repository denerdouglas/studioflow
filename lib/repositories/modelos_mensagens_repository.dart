import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../models/domain/mensagem_modelo.dart';

class ModelosMensagensRepository {
  final Future<Database> Function() _databaseProvider;

  ModelosMensagensRepository({Future<Database> Function()? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => DatabaseService.instance.database);

  Future<void> garantirPadroes(String comercioId) async {
    final db = await _databaseProvider();
    final agora = DateTime.now().toUtc().toIso8601String();
    for (final item in modelosMensagensPadrao.entries) {
      await db.insert('modelos_mensagens', {
        'id': 'modelo_${comercioId}_${item.key}',
        'comercio_id': comercioId,
        'chave': item.key,
        'nome': item.value.nome,
        'texto': item.value.texto,
        'texto_padrao': item.value.texto,
        'ativo': 1,
        'criado_em': agora,
        'atualizado_em': agora,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<List<ModeloMensagem>> listar(String comercioId) async {
    await garantirPadroes(comercioId);
    final db = await _databaseProvider();
    final rows = await db.query(
      'modelos_mensagens',
      where: 'comercio_id = ?',
      whereArgs: [comercioId],
      orderBy: 'nome COLLATE NOCASE',
    );
    return rows.map(_mapear).toList();
  }

  Future<ModeloMensagem> porChave(String comercioId, String chave) async {
    await garantirPadroes(comercioId);
    final db = await _databaseProvider();
    final rows = await db.query(
      'modelos_mensagens',
      where: 'comercio_id = ? AND chave = ?',
      whereArgs: [comercioId, chave],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Modelo de mensagem não encontrado.');
    return _mapear(rows.first);
  }

  Future<void> salvar(ModeloMensagem modelo) async {
    final db = await _databaseProvider();
    await db.update(
      'modelos_mensagens',
      {
        'nome': modelo.nome.trim(),
        'texto': modelo.texto.trim(),
        'ativo': modelo.ativo ? 1 : 0,
        'atualizado_em': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [modelo.id, modelo.comercioId],
    );
  }

  Future<void> restaurar(ModeloMensagem modelo) async {
    final db = await _databaseProvider();
    await db.update(
      'modelos_mensagens',
      {
        'texto': modelo.textoPadrao,
        'atualizado_em': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [modelo.id, modelo.comercioId],
    );
  }

  Future<void> duplicar(ModeloMensagem modelo) async {
    final db = await _databaseProvider();
    final sufixo = DateTime.now().microsecondsSinceEpoch;
    await db.insert('modelos_mensagens', {
      'id': 'modelo_${modelo.comercioId}_$sufixo',
      'comercio_id': modelo.comercioId,
      'chave': '${modelo.chave}_copia_$sufixo',
      'nome': '${modelo.nome} (cópia)',
      'texto': modelo.texto,
      'texto_padrao': modelo.textoPadrao,
      'ativo': 1,
      'origem_id': modelo.id,
      'criado_em': DateTime.now().toUtc().toIso8601String(),
      'atualizado_em': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static ModeloMensagem _mapear(Map<String, Object?> row) => ModeloMensagem(
    id: row['id'] as String,
    comercioId: row['comercio_id'] as String,
    chave: row['chave'] as String,
    nome: row['nome'] as String,
    texto: row['texto'] as String,
    textoPadrao: row['texto_padrao'] as String,
    ativo: row['ativo'] == 1,
  );
}
