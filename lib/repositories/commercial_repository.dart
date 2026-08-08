import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../services/product_lookup_service.dart';
import '../services/session_controller.dart';

enum SubscriptionStatus {
  trial,
  active,
  pending,
  overdue,
  gracePeriod,
  suspended,
  canceled,
}

class SubscriptionInfo {
  final String commerceId;
  final SubscriptionStatus status;
  final DateTime trialEndsAt;
  final double monthlyPrice;
  final DateTime? currentPeriodEndsAt;

  const SubscriptionInfo({
    required this.commerceId,
    required this.status,
    required this.trialEndsAt,
    required this.monthlyPrice,
    this.currentPeriodEndsAt,
  });

  int get trialDaysRemaining {
    final hours = trialEndsAt.difference(DateTime.now().toUtc()).inHours;
    final days = (hours / 24).ceil();
    if (days < 0) return 0;
    if (days > 30) return 30;
    return days;
  }
}

abstract interface class PaymentProvider {
  String get id;
  Future<SubscriptionStatus> simulatePayment({required double amount});
}

class MockPaymentProvider implements PaymentProvider {
  final bool approve;
  const MockPaymentProvider({this.approve = true});

  @override
  String get id => 'mock';

  @override
  Future<SubscriptionStatus> simulatePayment({required double amount}) async =>
      approve ? SubscriptionStatus.active : SubscriptionStatus.pending;
}

class CommercialRepository {
  final Future<Database> Function() _database;
  CommercialRepository({Future<Database> Function()? databaseProvider})
    : _database = databaseProvider ?? (() => DatabaseService.instance.database);

  String get _commerceId {
    final user = SessionController.instance.usuario;
    if (user == null) throw StateError('Sessão não autenticada.');
    return user.comercioId;
  }

  Future<SubscriptionInfo> subscription() async {
    final db = await _database();
    var rows = await db.query(
      'assinaturas',
      where: 'comercio_id = ?',
      whereArgs: [_commerceId],
      limit: 1,
    );
    
    if (rows.isEmpty) {
      final now = DateTime.now().toUtc();
      await db.insert('assinaturas', {
        'comercio_id': _commerceId,
        'status': SubscriptionStatus.trial.name,
        'inicio_trial': now.toIso8601String(),
        'fim_trial': now.add(const Duration(days: 30)).toIso8601String(),
        'valor_mensal': 24.99,
        'criado_em': now.toIso8601String(),
        'atualizado_em': now.toIso8601String(),
      });
      rows = await db.query(
        'assinaturas',
        where: 'comercio_id = ?',
        whereArgs: [_commerceId],
        limit: 1,
      );
    }
    
    final row = rows.first;
    return SubscriptionInfo(
      commerceId: _commerceId,
      status: SubscriptionStatus.values.firstWhere(
        (value) => value.name == row['status'],
        orElse: () => SubscriptionStatus.pending,
      ),
      trialEndsAt: DateTime.parse(row['fim_trial'] as String),
      monthlyPrice: (row['valor_mensal'] as num).toDouble(),
      currentPeriodEndsAt: DateTime.tryParse(
        row['periodo_atual_fim'] as String? ?? '',
      ),
    );
  }

  Future<SubscriptionInfo> simulateSubscription([
    PaymentProvider provider = const MockPaymentProvider(),
  ]) async {
    final before = await subscription();
    final after = await provider.simulatePayment(amount: before.monthlyPrice);
    final db = await _database();
    final now = DateTime.now().toUtc();
    await db.transaction((txn) async {
      await txn.update(
        'assinaturas',
        {
          'status': after.name,
          'provedor': provider.id,
          'periodo_atual_fim': now
              .add(const Duration(days: 30))
              .toIso8601String(),
          'atualizado_em': now.toIso8601String(),
        },
        where: 'comercio_id = ?',
        whereArgs: [_commerceId],
      );
      await txn.insert('assinatura_eventos', {
        'id': IdGenerator.temporal(),
        'comercio_id': _commerceId,
        'status_anterior': before.status.name,
        'status_novo': after.name,
        'motivo': 'Simulação local sem cobrança real',
        'provedor': provider.id,
        'criado_em': now.toIso8601String(),
      });
    });
    return subscription();
  }

  Future<List<Map<String, Object?>>> subscriptionHistory() async {
    final db = await _database();
    return db.query(
      'assinatura_eventos',
      where: 'comercio_id = ?',
      whereArgs: [_commerceId],
      orderBy: 'criado_em DESC',
    );
  }

  Future<Map<String, bool>> setupProgress() async {
    final db = await _database();
    final rows = await db.query(
      'progresso_configuracao',
      where: 'comercio_id = ?',
      whereArgs: [_commerceId],
      orderBy: 'etapa',
    );
    return {
      for (final row in rows) row['etapa'] as String: row['concluida'] == 1,
    };
  }

  Future<void> completeSetupStep(String step, bool completed) async {
    final db = await _database();
    await db.update(
      'progresso_configuracao',
      {
        'concluida': completed ? 1 : 0,
        'atualizado_em': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'comercio_id = ? AND etapa = ?',
      whereArgs: [_commerceId, step],
    );
  }

  Future<Map<String, bool>> featureFlags() async {
    final db = await _database();
    final rows = await db.query('feature_flags', orderBy: 'chave');
    return {
      for (final row in rows) row['chave'] as String: row['habilitada'] == 1,
    };
  }

  Future<void> suggestCatalogProduct(
    CatalogProduct product, {
    required bool consent,
  }) async {
    if (!consent) {
      throw StateError('É necessário consentir com a contribuição.');
    }
    final user = SessionController.instance.usuario;
    if (user == null) throw StateError('Sessão não autenticada.');
    final db = await _database();
    await db.insert('catalogo_sugestoes', {
      'id': IdGenerator.temporal(),
      'comercio_id': user.comercioId,
      'usuario_id': user.id,
      'gtin': product.gtin,
      'dados_json': jsonEncode(product.toJson()),
      'consentimento': 1,
      'status': 'pendente',
      'criado_em': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
