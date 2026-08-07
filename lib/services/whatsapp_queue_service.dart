import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../database/database_service.dart';
import '../repositories/whatsapp_fila_repository.dart';

class WhatsappQueueService {
  final Future<Database> Function() _databaseProvider;

  WhatsappQueueService({Future<Database> Function()? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => DatabaseService.instance.database);

  Future<void> enfileirar({
    DatabaseExecutor? txn,
    required String comercioId,
    required String destinatario,
    required String template,
    required Map<String, dynamic> payload,
    String? agendamentoId,
    String? idempotencyKey,
  }) async {
    final repo = WhatsappFilaRepository(
      databaseProvider: () async =>
          (txn as Database?) ?? await _databaseProvider(),
      comercioId: comercioId,
    );

    await repo.enfileirarMensagem(
      destinatario: destinatario,
      payload: jsonEncode(payload),
      agendamentoId: agendamentoId,
      templateId: template,
      provider: 'system',
      idempotencyKey: idempotencyKey,
      txn: txn,
    );
  }

  Future<void> enfileirarDireto({
    DatabaseExecutor? txn,
    required String comercioId,
    required String destinatario,
    required String texto,
    String? agendamentoId,
    String? idempotencyKey,
  }) async {
    final repo = WhatsappFilaRepository(
      databaseProvider: () async =>
          (txn as Database?) ?? await _databaseProvider(),
      comercioId: comercioId,
    );

    await repo.enfileirarMensagem(
      destinatario: destinatario,
      payload: jsonEncode({'texto': texto}),
      agendamentoId: agendamentoId,
      templateId: 'texto_livre',
      provider: 'system',
      idempotencyKey: idempotencyKey,
      txn: txn,
    );
  }
}
