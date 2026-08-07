import 'package:sqflite_common/sqlite_api.dart';
import '../models/domain/whatsapp_fila.dart';
import '../database/database_service.dart';
import 'package:uuid/uuid.dart';

class WhatsappFilaRepository {
  final Future<Database> Function() _databaseProvider;
  final String _comercioId;

  WhatsappFilaRepository({
    Future<Database> Function()? databaseProvider,
    required this._comercioId,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseService.instance.database);

  String _uuid() => const Uuid().v4();

  Future<WhatsappFilaMensagem?> enfileirarMensagem({
    required String destinatario,
    required String payload,
    String? clienteId,
    String? agendamentoId,
    String? provider,
    String? idempotencyKey,
    String? templateId,
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? await _databaseProvider();

    // Idempotency Check
    if (idempotencyKey != null && provider != null) {
      final existing = await db.query(
        'whatsapp_fila',
        where:
            'business_id = ? AND provider = ? AND idempotency_key = ? AND deleted_at IS NULL',
        whereArgs: [_comercioId, provider, idempotencyKey],
      );
      if (existing.isNotEmpty) {
        return WhatsappFilaMensagem.fromMap(existing.first);
      }
    }

    final id = _uuid();
    final now = DateTime.now();

    final msg = WhatsappFilaMensagem(
      id: id,
      businessId: _comercioId,
      clienteId: clienteId,
      destinatario: destinatario,
      agendamentoId: agendamentoId,
      status: StatusFilaWhatsapp.naFila,
      idempotencyKey: idempotencyKey,
      provider: provider,
      templateId: templateId,
      payload: payload,
      createdAt: now,
      updatedAt: now,
    );

    await db.insert('whatsapp_fila', msg.toMap());
    return msg;
  }

  Future<void> atualizarStatus(
    String id,
    StatusFilaWhatsapp novoStatus, {
    String? erro,
    String? providerMessageId,
  }) async {
    final db = await _databaseProvider();
    final updates = <String, Object?>{
      'status': novoStatus.dbValue,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (erro != null) updates['erro'] = erro;
    if (providerMessageId != null) {
      updates['provider_message_id'] = providerMessageId;
    }

    if (novoStatus == StatusFilaWhatsapp.entregue) {
      updates['delivered_at'] = DateTime.now().toIso8601String();
    } else if (novoStatus == StatusFilaWhatsapp.lida) {
      updates['read_at'] = DateTime.now().toIso8601String();
    } else if (novoStatus == StatusFilaWhatsapp.falhou) {
      updates['failed_at'] = DateTime.now().toIso8601String();
    } else if (novoStatus == StatusFilaWhatsapp.enviando) {
      updates['sent_at'] = DateTime.now().toIso8601String();
    }

    await db.update(
      'whatsapp_fila',
      updates,
      where: 'id = ? AND business_id = ?',
      whereArgs: [id, _comercioId],
    );
  }

  Future<List<WhatsappFilaMensagem>> consultarFila() async {
    final db = await _databaseProvider();
    final result = await db.query(
      'whatsapp_fila',
      where: 'business_id = ? AND deleted_at IS NULL',
      whereArgs: [_comercioId],
      orderBy: 'created_at DESC',
    );
    return result.map((e) => WhatsappFilaMensagem.fromMap(e)).toList();
  }

  Future<WhatsappFilaMensagem?> buscarPorAgendamento(
    String agendamentoId,
  ) async {
    final db = await _databaseProvider();
    final result = await db.query(
      'whatsapp_fila',
      where: 'business_id = ? AND agendamento_id = ? AND deleted_at IS NULL',
      whereArgs: [_comercioId, agendamentoId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (result.isNotEmpty) {
      return WhatsappFilaMensagem.fromMap(result.first);
    }
    return null;
  }
}
