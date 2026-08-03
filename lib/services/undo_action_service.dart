import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import 'session_controller.dart';

class UndoableAction {
  final String message;
  final String entity;
  final String entityId;
  final String action;
  final Map<String, Object?>? previousState;
  final Map<String, Object?>? newState;
  final Future<void> Function() execute;
  final Future<void> Function() undo;

  const UndoableAction({
    required this.message,
    required this.entity,
    required this.entityId,
    required this.action,
    this.previousState,
    this.newState,
    required this.execute,
    required this.undo,
  });
}

class UndoActionService {
  final Future<Database> Function() _databaseProvider;

  UndoActionService({Future<Database> Function()? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => DatabaseService.instance.database);

  Future<void> perform(BuildContext context, UndoableAction action) async {
    final user = SessionController.instance.usuario;
    if (user == null) throw StateError('Sessão não autenticada.');
    await action.execute();
    final db = await _databaseProvider();
    final auditId = IdGenerator.temporal();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((tx) async {
      await tx.insert('undo_auditoria', {
        'id': auditId,
        'comercio_id': user.comercioId,
        'unidade_id': SessionController.instance.unidadeAtiva,
        'usuario_id': user.id,
        'entidade': action.entity,
        'entidade_id': action.entityId,
        'acao': action.action,
        'estado_anterior': action.previousState == null
            ? null
            : jsonEncode(action.previousState),
        'estado_novo': action.newState == null
            ? null
            : jsonEncode(action.newState),
        'criado_em': now,
      });
      await _sync(
        tx,
        user.comercioId,
        action.entity,
        action.entityId,
        '${action.action}_executada',
        action.newState ?? const {},
      );
    });

    if (!context.mounted) return;
    var reversed = false;
    final accessible =
        MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(action.message),
        duration: Duration(seconds: accessible ? 12 : 7),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Desfazer',
          onPressed: () async {
            if (reversed) return;
            reversed = true;
            await action.undo();
            final reversedAt = DateTime.now().toUtc().toIso8601String();
            await db.transaction((tx) async {
              await tx.update(
                'undo_auditoria',
                {'revertida': 1, 'revertida_em': reversedAt},
                where: 'id = ? AND comercio_id = ? AND revertida = 0',
                whereArgs: [auditId, user.comercioId],
              );
              await _sync(
                tx,
                user.comercioId,
                action.entity,
                action.entityId,
                '${action.action}_revertida',
                action.previousState ?? const {},
              );
            });
          },
        ),
      ),
    );
  }

  static Future<void> _sync(
    DatabaseExecutor db,
    String commerceId,
    String entity,
    String entityId,
    String operation,
    Map<String, Object?> payload,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('fila_sincronizacao', {
      'id': IdGenerator.temporal(),
      'comercio_id': commerceId,
      'unidade_id': SessionController.instance.unidadeAtiva,
      'entidade': entity,
      'entidade_id': entityId,
      'operacao': operation,
      'payload_json': jsonEncode(payload),
      'status': 'pendente',
      'criada_em': now,
      'atualizada_em': now,
    });
  }
}
