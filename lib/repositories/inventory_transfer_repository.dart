import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../models/domain/acesso.dart';
import '../services/session_controller.dart';

final class InventoryTransferRepository {
  final Future<Database> Function() _database;

  InventoryTransferRepository({Future<Database> Function()? databaseProvider})
    : _database = databaseProvider ?? (() => DatabaseService.instance.database);

  Future<String> transferToStore({
    required String sourceProductId,
    required double quantity,
    required String reason,
  }) async {
    final user = SessionController.instance.usuario;
    if (user == null || !user.podeAcao(AcaoPermissao.movimentarEstoque)) {
      throw StateError('Você não possui permissão para transferir estoque.');
    }
    if (quantity <= 0 || reason.trim().isEmpty) {
      throw StateError('Informe quantidade e motivo da transferência.');
    }
    final db = await _database();
    return db.transaction((txn) async {
      final sourceRows = await txn.query(
        'estoque',
        where: "id=? AND comercio_id=? AND estoque_destino='salao'",
        whereArgs: [sourceProductId, user.comercioId],
        limit: 1,
      );
      if (sourceRows.isEmpty) {
        throw StateError('Produto não encontrado no estoque do salão.');
      }
      final source = sourceRows.single;
      final sourceQuantity = (source['quantidade_atual'] as num? ?? 0)
          .toDouble();
      if (quantity > sourceQuantity) {
        throw StateError('Quantidade maior que o saldo disponível.');
      }
      final barcode = source['codigo_barras'] as String?;
      final destinationRows = await txn.query(
        'estoque',
        where: barcode?.isNotEmpty == true
            ? "comercio_id=? AND estoque_destino='loja' AND codigo_barras=?"
            : "comercio_id=? AND estoque_destino='loja' "
                  'AND lower(trim(nome))=lower(trim(?))',
        whereArgs: [
          user.comercioId,
          barcode?.isNotEmpty == true ? barcode : source['nome'],
        ],
        limit: 1,
      );
      final destinationId = destinationRows.isEmpty
          ? 'prd_${IdGenerator.temporal()}'
          : destinationRows.single['id'] as String;
      final destinationQuantity = destinationRows.isEmpty
          ? 0.0
          : (destinationRows.single['quantidade_atual'] as num).toDouble();
      final now = DateTime.now().toUtc();
      if (destinationRows.isEmpty) {
        final copy = Map<String, Object?>.from(source)
          ..['id'] = destinationId
          ..['estoque_destino'] = 'loja'
          ..['quantidade_atual'] = 0.0
          ..['preco_venda'] = 0.0
          ..['margem'] = 0.0
          ..['data_cadastro'] = now.toIso8601String()
          ..['atualizado_em'] = now.toIso8601String();
        await txn.insert('estoque', copy);
      }
      await txn.update(
        'estoque',
        {
          'quantidade_atual': sourceQuantity - quantity,
          'atualizado_em': now.toIso8601String(),
        },
        where: 'id=? AND comercio_id=?',
        whereArgs: [sourceProductId, user.comercioId],
      );
      await txn.update(
        'estoque',
        {
          'quantidade_atual': destinationQuantity + quantity,
          'atualizado_em': now.toIso8601String(),
        },
        where: 'id=? AND comercio_id=?',
        whereArgs: [destinationId, user.comercioId],
      );
      final transferId = 'trf_${IdGenerator.temporal()}';
      await txn.insert('transferencias_estoque', {
        'id': transferId,
        'comercio_id': user.comercioId,
        'produto_origem_id': sourceProductId,
        'produto_destino_id': destinationId,
        'origem': 'salao',
        'destino': 'loja',
        'quantidade': quantity,
        'motivo': reason.trim(),
        'usuario_id': user.id,
        'criado_em': now.toIso8601String(),
      });
      await _movement(
        txn,
        id: '${transferId}_out',
        businessId: user.comercioId,
        productId: sourceProductId,
        type: 'saida',
        quantity: quantity,
        before: sourceQuantity,
        after: sourceQuantity - quantity,
        reason: reason,
        userId: user.id,
        transferId: transferId,
        now: now,
      );
      await _movement(
        txn,
        id: '${transferId}_in',
        businessId: user.comercioId,
        productId: destinationId,
        type: 'entrada',
        quantity: quantity,
        before: destinationQuantity,
        after: destinationQuantity + quantity,
        reason: reason,
        userId: user.id,
        transferId: transferId,
        now: now,
      );
      return transferId;
    });
  }

  Future<void> _movement(
    DatabaseExecutor db, {
    required String id,
    required String businessId,
    required String productId,
    required String type,
    required double quantity,
    required double before,
    required double after,
    required String reason,
    required String userId,
    required String transferId,
    required DateTime now,
  }) => db.insert('movimentacoes_estoque', {
    'id': id,
    'comercio_id': businessId,
    'item_estoque_id': productId,
    'tipo': type,
    'quantidade': quantity,
    'quantidade_anterior': before,
    'quantidade_posterior': after,
    'data': now.toIso8601String(),
    'motivo': 'Transferência: ${reason.trim()}',
    'usuario_responsavel_id': userId,
    'origem': 'transferencia_estoque',
    'referencia_id': transferId,
  });
}
