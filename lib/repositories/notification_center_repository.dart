import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../services/notification_service.dart';
import '../services/session_controller.dart';

abstract interface class LocalNotificationGateway {
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime date,
    String? payload,
    required String category,
  });

  Future<void> cancel(int id);
}

class PluginLocalNotificationGateway implements LocalNotificationGateway {
  final NotificationService _service;
  PluginLocalNotificationGateway([NotificationService? service])
    : _service = service ?? NotificationService();

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime date,
    String? payload,
    required String category,
  }) => _service.scheduleNotification(
    id: id,
    title: title,
    body: body,
    scheduledDate: date,
    payload: payload,
    channelId: 'studioflow_$category',
    channelName: category == 'agenda' ? 'Agenda' : 'Financeiro',
  );

  @override
  Future<void> cancel(int id) => _service.cancelNotification(id);
}

class NotificationCenterRepository {
  final Future<Database> Function() _databaseProvider;
  final LocalNotificationGateway _gateway;
  final String? _businessIdOverride;

  NotificationCenterRepository({
    Future<Database> Function()? databaseProvider,
    LocalNotificationGateway? gateway,
    String? businessId,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseService.instance.database),
       _gateway = gateway ?? PluginLocalNotificationGateway(),
       _businessIdOverride = businessId;

  String get _businessId =>
      _businessIdOverride ?? SessionController.instance.usuario!.comercioId;

  int localId(String key) =>
      NotificationService().generateId('$_businessId:$key');

  Future<bool> enabled(String category, String channel) async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'notification_preferences',
      columns: ['enabled'],
      where: 'business_id = ? AND category = ? AND channel = ?',
      whereArgs: [_businessId, category, channel],
      limit: 1,
    );
    return rows.isEmpty || (rows.first['enabled'] as num).toInt() == 1;
  }

  Future<void> setEnabled(String category, String channel, bool value) async {
    final db = await _databaseProvider();
    await db.insert('notification_preferences', {
      'id': '$category:$channel',
      'business_id': _businessId,
      'category': category,
      'channel': channel,
      'enabled': value ? 1 : 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> schedule({
    required String key,
    required String type,
    required String category,
    required String entity,
    required String entityId,
    required String title,
    required String body,
    required DateTime date,
    required String route,
    String priority = 'normal',
  }) async {
    final db = await _databaseProvider();
    final now = DateTime.now().toUtc().toIso8601String();
    final internalEnabled = await enabled(category, 'interna');
    final localEnabled = await enabled(category, 'local');
    if (internalEnabled) {
      await db.insert('notificacoes', {
        'id': 'notification_${_businessId}_$key',
        'comercio_id': _businessId,
        'tipo': type,
        'entidade': entity,
        'referencia_id': entityId,
        'titulo': title,
        'mensagem': body,
        'prioridade': priority,
        'canal': 'interna',
        'status': 'pendente',
        'rota': route,
        'data_criacao': now,
        'data_agendada': date.toUtc().toIso8601String(),
        'idempotency_key': key,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    if (localEnabled) {
      await _gateway.schedule(
        id: localId(key),
        title: title,
        body: body,
        date: date,
        payload: route,
        category: category,
      );
    }
  }

  Future<void> cancelEntity(String entity, String entityId) async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'notificacoes',
      columns: ['idempotency_key'],
      where:
          "comercio_id = ? AND entidade = ? AND referencia_id = ? AND status = 'pendente'",
      whereArgs: [_businessId, entity, entityId],
    );
    for (final row in rows) {
      final key = row['idempotency_key'] as String?;
      if (key != null) await _gateway.cancel(localId(key));
    }
    await db.update(
      'notificacoes',
      {
        'status': 'cancelada',
        'canceled_at': DateTime.now().toUtc().toIso8601String(),
      },
      where:
          "comercio_id = ? AND entidade = ? AND referencia_id = ? AND status = 'pendente'",
      whereArgs: [_businessId, entity, entityId],
    );
  }

  Future<List<Map<String, Object?>>> list({String? category}) async {
    final db = await _databaseProvider();
    return db.query(
      'notificacoes',
      where: category == null
          ? 'comercio_id = ?'
          : 'comercio_id = ? AND tipo LIKE ?',
      whereArgs: category == null ? [_businessId] : [_businessId, '$category%'],
      orderBy: 'data_criacao DESC',
    );
  }

  Future<void> markRead(String id) async {
    final db = await _databaseProvider();
    await db.update(
      'notificacoes',
      {'status': 'lida', 'read_at': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [id, _businessId],
    );
  }

  Future<bool> entityBelongsToBusiness(String entity, String entityId) async {
    final db = await _databaseProvider();
    if (entity == 'stock_product') {
      final products = await db.query(
        'produtos_loja',
        columns: ['id'],
        where: 'id = ? AND comercio_id = ?',
        whereArgs: [entityId, _businessId],
        limit: 1,
      );
      if (products.isNotEmpty) return true;
    }
    final mapping = switch (entity) {
      'appointment' => ('agendamentos', 'comercio_id'),
      'account_payable' => ('accounts_payable', 'business_id'),
      'financial_movement' => ('movimentacoes_financeiras', 'comercio_id'),
      'client' => ('clientes', 'comercio_id'),
      'stock_product' => ('estoque', 'business_id'),
      _ => null,
    };
    if (mapping == null) return false;
    final rows = await db.query(
      mapping.$1,
      columns: ['id'],
      where: 'id = ? AND ${mapping.$2} = ?',
      whereArgs: [entityId, _businessId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}
