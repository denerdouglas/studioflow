import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../services/session_controller.dart';
import 'notification_center_repository.dart';

class AccountPayable {
  final String id;
  final String businessId;
  final String description;
  final String category;
  final String? supplier;
  final double amount;
  final String type;
  final DateTime dueDate;
  final String recurrence;
  final String status;
  final DateTime? paidAt;
  final String? paymentMethod;
  final String notes;
  final String? receiptUri;
  final String? seriesId;
  final String? occurrenceKey;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AccountPayable({
    required this.id,
    required this.businessId,
    required this.description,
    required this.category,
    this.supplier,
    required this.amount,
    required this.type,
    required this.dueDate,
    this.recurrence = 'nenhuma',
    this.status = 'pendente',
    this.paidAt,
    this.paymentMethod,
    this.notes = '',
    this.receiptUri,
    this.seriesId,
    this.occurrenceKey,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'business_id': businessId,
    'description': description,
    'category': category,
    'supplier': supplier,
    'amount': amount,
    'type': type,
    'due_date': dueDate.toIso8601String(),
    'recurrence': recurrence,
    'status': status,
    'paid_at': paidAt?.toIso8601String(),
    'payment_method': paymentMethod,
    'notes': notes,
    'receipt_uri': receiptUri,
    'series_id': seriesId,
    'occurrence_key': occurrenceKey,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory AccountPayable.fromMap(Map<String, Object?> map) => AccountPayable(
    id: map['id'] as String,
    businessId: map['business_id'] as String,
    description: map['description'] as String,
    category: map['category'] as String,
    supplier: map['supplier'] as String?,
    amount: (map['amount'] as num).toDouble(),
    type: map['type'] as String,
    dueDate: DateTime.parse(map['due_date'] as String),
    recurrence: map['recurrence'] as String,
    status: map['status'] as String,
    paidAt: map['paid_at'] == null
        ? null
        : DateTime.parse(map['paid_at'] as String),
    paymentMethod: map['payment_method'] as String?,
    notes: map['notes'] as String? ?? '',
    receiptUri: map['receipt_uri'] as String?,
    seriesId: map['series_id'] as String?,
    occurrenceKey: map['occurrence_key'] as String?,
    createdAt: DateTime.parse(map['created_at'] as String),
    updatedAt: DateTime.parse(map['updated_at'] as String),
  );

  AccountPayable copyWith({
    String? description,
    String? category,
    String? supplier,
    double? amount,
    String? type,
    DateTime? dueDate,
    String? recurrence,
    String? status,
    DateTime? paidAt,
    String? paymentMethod,
    String? notes,
    String? receiptUri,
  }) => AccountPayable(
    id: id,
    businessId: businessId,
    description: description ?? this.description,
    category: category ?? this.category,
    supplier: supplier ?? this.supplier,
    amount: amount ?? this.amount,
    type: type ?? this.type,
    dueDate: dueDate ?? this.dueDate,
    recurrence: recurrence ?? this.recurrence,
    status: status ?? this.status,
    paidAt: paidAt ?? this.paidAt,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    notes: notes ?? this.notes,
    receiptUri: receiptUri ?? this.receiptUri,
    seriesId: seriesId,
    occurrenceKey: occurrenceKey,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );
}

class AccountsPayableSummary {
  final int dueToday;
  final int dueTomorrow;
  final int overdue;
  final double pendingMonth;
  final double paidMonth;
  const AccountsPayableSummary({
    required this.dueToday,
    required this.dueTomorrow,
    required this.overdue,
    required this.pendingMonth,
    required this.paidMonth,
  });
}

class AccountsPayableRepository {
  final Future<Database> Function() _databaseProvider;
  final String? _businessIdOverride;
  final NotificationCenterRepository? _notificationsOverride;

  AccountsPayableRepository({
    Future<Database> Function()? databaseProvider,
    String? businessId,
    NotificationCenterRepository? notifications,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseService.instance.database),
       _businessIdOverride = businessId,
       _notificationsOverride = notifications;

  String get _businessId =>
      _businessIdOverride ?? SessionController.instance.usuario!.comercioId;
  NotificationCenterRepository get _notifications =>
      _notificationsOverride ??
      NotificationCenterRepository(
        databaseProvider: _databaseProvider,
        businessId: _businessId,
      );

  void _validate(AccountPayable item) {
    if (item.businessId != _businessId) throw StateError('Conta inválida.');
    if (item.description.trim().isEmpty || item.amount <= 0) {
      throw ArgumentError('Descrição e valor são obrigatórios.');
    }
  }

  Future<void> save(AccountPayable item) async {
    _validate(item);
    final db = await _databaseProvider();
    await db.insert(
      'accounts_payable',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _schedule(item);
  }

  Future<List<AccountPayable>> list({String? type, String? status}) async {
    final db = await _databaseProvider();
    final clauses = <String>['business_id = ?'];
    final args = <Object?>[_businessId];
    if (type != null) {
      clauses.add('type = ?');
      args.add(type);
    }
    if (status != null) {
      clauses.add(
        status == 'vencida'
            ? "status = 'pendente' AND due_date < ?"
            : 'status = ?',
      );
      args.add(status == 'vencida' ? DateTime.now().toIso8601String() : status);
    }
    final rows = await db.query(
      'accounts_payable',
      where: clauses.join(' AND '),
      whereArgs: args,
      orderBy: 'due_date, description',
    );
    return rows.map(AccountPayable.fromMap).toList();
  }

  Future<AccountPayable?> get(String id) async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'accounts_payable',
      where: 'id = ? AND business_id = ?',
      whereArgs: [id, _businessId],
      limit: 1,
    );
    return rows.isEmpty ? null : AccountPayable.fromMap(rows.single);
  }

  Future<AccountsPayableSummary> summary([DateTime? reference]) async {
    final db = await _databaseProvider();
    final now = reference ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final monthEnd = DateTime(now.year, now.month + 1);
    final rows = await db.query(
      'accounts_payable',
      where: 'business_id = ?',
      whereArgs: [_businessId],
    );
    final items = rows.map(AccountPayable.fromMap);
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    final active = items.where((item) => item.status == 'pendente').toList();
    return AccountsPayableSummary(
      dueToday: active.where((item) => sameDay(item.dueDate, today)).length,
      dueTomorrow: active
          .where((item) => sameDay(item.dueDate, tomorrow))
          .length,
      overdue: active.where((item) => item.dueDate.isBefore(today)).length,
      pendingMonth: active
          .where(
            (item) =>
                !item.dueDate.isBefore(DateTime(now.year, now.month)) &&
                item.dueDate.isBefore(monthEnd),
          )
          .fold(0, (sum, item) => sum + item.amount),
      paidMonth: items
          .where(
            (item) =>
                item.status == 'paga' &&
                item.paidAt != null &&
                item.paidAt!.year == now.year &&
                item.paidAt!.month == now.month,
          )
          .fold(0, (sum, item) => sum + item.amount),
    );
  }

  Future<void> refreshOverdue([DateTime? reference]) async {
    final now = reference ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final items = await list(status: 'vencida');
    for (final item in items) {
      final days = today
          .difference(
            DateTime(item.dueDate.year, item.dueDate.month, item.dueDate.day),
          )
          .inDays;
      await _notifications.schedule(
        key:
            'accounts_payable:${item.id}:overdue:${today.toIso8601String().substring(0, 10)}',
        type: 'contas_pagar_vencida',
        category: 'contas_pagar',
        entity: 'account_payable',
        entityId: item.id,
        title: 'Conta vencida',
        body:
            '${item.description} está vencida há $days dia${days == 1 ? '' : 's'}',
        date: DateTime.now().add(const Duration(seconds: 1)),
        route: '/financeiro/contas-pagar/${item.id}',
        priority: 'alta',
      );
    }
  }

  Future<void> markPaid(String id, String paymentMethod) async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'accounts_payable',
      where: 'id = ? AND business_id = ?',
      whereArgs: [id, _businessId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Conta não encontrada.');
    final item = AccountPayable.fromMap(rows.first);
    if (item.status == 'paga') return;
    final now = DateTime.now();
    await db.update(
      'accounts_payable',
      {
        'status': 'paga',
        'paid_at': now.toIso8601String(),
        'payment_method': paymentMethod,
        'updated_at': now.toIso8601String(),
      },
      where: 'id = ? AND business_id = ?',
      whereArgs: [id, _businessId],
    );
    await _notifications.cancelEntity('account_payable', id);
    await _createNextOccurrence(item);
  }

  Future<void> cancel(String id) async {
    final db = await _databaseProvider();
    await db.update(
      'accounts_payable',
      {'status': 'cancelada', 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ? AND business_id = ?',
      whereArgs: [id, _businessId],
    );
    await _notifications.cancelEntity('account_payable', id);
  }

  Future<void> _schedule(AccountPayable item) async {
    await _notifications.cancelEntity('account_payable', item.id);
    if (item.status != 'pendente') return;
    final value = 'R\$ ${item.amount.toStringAsFixed(2).replaceAll('.', ',')}';
    final day = DateTime(
      item.dueDate.year,
      item.dueDate.month,
      item.dueDate.day,
      9,
    );
    await _notifications.schedule(
      key: 'account:${item.id}:day_before',
      type: 'contas_pagar_amanha',
      category: 'contas_pagar',
      entity: 'account_payable',
      entityId: item.id,
      title: 'Conta vence amanhã',
      body: '${item.description} vence amanhã — $value',
      date: day.subtract(const Duration(days: 1)),
      route: '/financeiro/contas-pagar/${item.id}',
    );
    await _notifications.schedule(
      key: 'account:${item.id}:due',
      type: 'contas_pagar_hoje',
      category: 'contas_pagar',
      entity: 'account_payable',
      entityId: item.id,
      title: 'Conta vence hoje',
      body: '${item.description} vence hoje — $value',
      date: day,
      route: '/financeiro/contas-pagar/${item.id}',
      priority: 'alta',
    );
  }

  Future<void> _createNextOccurrence(AccountPayable item) async {
    if (item.type != 'fixa' || item.recurrence == 'nenhuma') return;
    final nextDue = switch (item.recurrence) {
      'semanal' => item.dueDate.add(const Duration(days: 7)),
      'quinzenal' => item.dueDate.add(const Duration(days: 15)),
      'mensal' => _sameDayNextMonth(item.dueDate),
      'anual' => _sameDayNextYear(item.dueDate),
      _ => null,
    };
    if (nextDue == null) return;
    final series = item.seriesId ?? item.id;
    final key = '$series:${nextDue.year}-${nextDue.month}-${nextDue.day}';
    final now = DateTime.now();
    await save(
      AccountPayable(
        id: '${item.id}_${nextDue.millisecondsSinceEpoch}',
        businessId: _businessId,
        description: item.description,
        category: item.category,
        supplier: item.supplier,
        amount: item.amount,
        type: item.type,
        dueDate: nextDue,
        recurrence: item.recurrence,
        notes: item.notes,
        seriesId: series,
        occurrenceKey: key,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  static DateTime _sameDayNextMonth(DateTime date) {
    final first = DateTime(date.year, date.month + 1);
    final lastDay = DateTime(first.year, first.month + 1, 0).day;
    return DateTime(first.year, first.month, date.day.clamp(1, lastDay));
  }

  static DateTime _sameDayNextYear(DateTime date) {
    final lastDay = DateTime(date.year + 1, date.month + 1, 0).day;
    return DateTime(date.year + 1, date.month, date.day.clamp(1, lastDay));
  }
}
