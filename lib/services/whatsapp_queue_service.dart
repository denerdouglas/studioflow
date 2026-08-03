import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../core/utils/id_generator.dart';
import '../database/database_service.dart';

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
  }) async {
    final db = txn ?? await _databaseProvider();
    final now = DateTime.now().toUtc().toIso8601String();

    await db.insert('whatsapp_fila', {
      'id': 'wa_${IdGenerator.temporal()}',
      'comercio_id': comercioId,
      'destinatario': destinatario,
      'template': template,
      'payload_json': jsonEncode(payload),
      'status': 'pendente',
      'agendamento_id': agendamentoId,
      'criado_em': now,
      'atualizado_em': now,
    });
  }

  Future<void> enfileirarDireto({
    DatabaseExecutor? txn,
    required String comercioId,
    required String destinatario,
    required String texto,
    String? agendamentoId,
  }) async {
    final db = txn ?? await _databaseProvider();
    final now = DateTime.now().toUtc().toIso8601String();

    await db.insert('whatsapp_fila', {
      'id': 'wa_${IdGenerator.temporal()}',
      'comercio_id': comercioId,
      'destinatario': destinatario,
      'template': 'texto_livre',
      'payload_json': jsonEncode({'texto': texto}),
      'status': 'pendente',
      'agendamento_id': agendamentoId,
      'criado_em': now,
      'atualizado_em': now,
    });
  }
}
