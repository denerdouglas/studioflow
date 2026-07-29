import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../services/session_controller.dart';

class PrivacyRepository {
  final Future<Database> Function() _database;
  PrivacyRepository({Future<Database> Function()? databaseProvider})
    : _database = databaseProvider ?? (() => DatabaseService.instance.database);

  Future<String> exportCurrentUserData() async {
    final user = SessionController.instance.usuario;
    if (user == null) throw StateError('Sessão não autenticada.');
    final db = await _database();
    final commerce = await db.query(
      'comercios',
      where: 'id = ?',
      whereArgs: [user.comercioId],
      limit: 1,
    );
    final users = await db.query(
      'usuarios',
      columns: ['id', 'nome', 'telefone', 'email_login', 'funcao', 'ativo'],
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [user.id, user.comercioId],
    );
    return const JsonEncoder.withIndent('  ').convert({
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'commerce': commerce,
      'user': users,
      'notice':
          'Hashes, salts, dados financeiros e dados de terceiros não são exportados.',
    });
  }

  Future<void> requestAccountDeletion() async {
    final user = SessionController.instance.usuario;
    if (user == null) throw StateError('Sessão não autenticada.');
    final db = await _database();
    await db.insert('solicitacoes_privacidade', {
      'id': 'privacy_${IdGenerator.temporal()}',
      'comercio_id': user.comercioId,
      'titular_tipo': 'usuario',
      'titular_id': user.id,
      'tipo': 'exclusao_conta',
      'status': 'pendente_confirmacao_backend',
      'solicitado_em': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<bool> hasPendingDeletionRequest() async {
    final user = SessionController.instance.usuario;
    if (user == null) return false;
    final db = await _database();
    final rows = await db.query(
      'solicitacoes_privacidade',
      columns: ['id'],
      where:
          "comercio_id = ? AND titular_id = ? AND tipo = 'exclusao_conta' AND concluido_em IS NULL",
      whereArgs: [user.comercioId, user.id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}
