import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';

abstract final class MigrationV42 {
  static Future<void> executar(Database db) async {
    // MOVIMENTACOES_ESTOQUE
    final columns = await _getColunas(db, 'movimentacoes_estoque');
    if (columns.isNotEmpty) {
      await _addColumn(
        db,
        'movimentacoes_estoque',
        columns,
        'finalidade',
        'TEXT',
      );
      await _addColumn(
        db,
        'movimentacoes_estoque',
        columns,
        'business_id',
        'TEXT',
      );
      await _addColumn(
        db,
        'movimentacoes_estoque',
        columns,
        'comercio_id',
        'TEXT',
      );
      await _addColumn(
        db,
        'movimentacoes_estoque',
        columns,
        'idempotency_key',
        'TEXT',
      );
      await _addColumn(db, 'movimentacoes_estoque', columns, 'origem', 'TEXT');
      await _addColumn(
        db,
        'movimentacoes_estoque',
        columns,
        'referencia_id',
        'TEXT',
      );
      await _addColumn(
        db,
        'movimentacoes_estoque',
        columns,
        'justificativa_negativo',
        'TEXT',
      );

      // Criar índices, se faltarem
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_movimentacoes_idempotency 
        ON movimentacoes_estoque(idempotency_key) 
        WHERE idempotency_key IS NOT NULL
      ''');
    }
  }

  static Future<Set<String>> _getColunas(Database db, String tabela) async {
    try {
      final rows = await db.rawQuery('PRAGMA table_info($tabela)');
      return rows
          .map((r) => r['name']?.toString().toLowerCase())
          .whereType<String>()
          .toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> _addColumn(
    Database db,
    String table,
    Set<String> columns,
    String column,
    String type,
  ) async {
    if (!columns.contains(column.toLowerCase())) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
      debugPrint('MigrationV42: $table.$column adicionada ($type)');
    }
  }
}
