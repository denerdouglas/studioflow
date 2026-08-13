import 'package:sqflite/sqflite.dart';

/// Classificação financeira mínima para os centros de resultado.
///
/// O backfill é deliberadamente conservador: somente relações estruturais
/// classificam registros antigos. Textos livres nunca são usados como prova.
abstract final class MigrationV39 {
  static Future<void> executar(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    final names = tables.map((row) => '${row['name']}').toSet();
    if (!names.contains('movimentacoes_financeiras')) return;

    await _addColumn(db, 'centro_resultado', 'TEXT');
    await _addColumn(db, 'entidade_origem', 'TEXT');
    await _addColumn(db, 'entidade_origem_id', 'TEXT');

    await db.execute('''CREATE INDEX IF NOT EXISTS idx_financeiro_centro_data
      ON movimentacoes_financeiras(comercio_id, centro_resultado, data)''');

    // Serviços: vínculos nativos são evidência inequívoca.
    await db.rawUpdate('''UPDATE movimentacoes_financeiras
      SET centro_resultado='salao',
          entidade_origem=CASE
            WHEN agendamento_id IS NOT NULL THEN 'agendamento'
            ELSE 'servico'
          END,
          entidade_origem_id=COALESCE(agendamento_id, servico_id)
      WHERE centro_resultado IS NULL
        AND (agendamento_id IS NOT NULL OR servico_id IS NOT NULL)''');

    // Pacotes atuais têm uma referência determinística já usada pelo módulo.
    if (names.contains('pacotes_vendidos')) {
      await db.rawUpdate('''UPDATE movimentacoes_financeiras AS m
        SET centro_resultado='salao', entidade_origem='pacote_venda',
            entidade_origem_id=substr(m.observacoes, length('pacote_venda_id=')+1)
        WHERE m.centro_resultado IS NULL
          AND m.observacoes LIKE 'pacote_venda_id=%'
          AND EXISTS (SELECT 1 FROM pacotes_vendidos p
            WHERE p.id=substr(m.observacoes, length('pacote_venda_id=')+1)
              AND p.business_id=m.comercio_id)''');
    }

    // Pagamentos diretos do PDV usam IDs derivados da venda.
    if (names.contains('pdv_vendas')) {
      await db.rawUpdate('''UPDATE movimentacoes_financeiras AS m
        SET centro_resultado='loja', entidade_origem='pdv_venda',
            entidade_origem_id=(SELECT v.id FROM pdv_vendas v
              WHERE v.comercio_id=m.comercio_id
                AND (m.id LIKE v.id || '_p%' OR m.id LIKE v.id || '_estorno%')
              LIMIT 1)
        WHERE m.centro_resultado IS NULL AND EXISTS (
          SELECT 1 FROM pdv_vendas v WHERE v.comercio_id=m.comercio_id
            AND (m.id LIKE v.id || '_p%' OR m.id LIKE v.id || '_estorno%'))''');
    }

    if (names.contains('comanda_loja_pagamentos')) {
      await db.rawUpdate('''UPDATE movimentacoes_financeiras AS m
        SET centro_resultado='loja', entidade_origem='comanda',
            entidade_origem_id=(SELECT p.comanda_id
              FROM comanda_loja_pagamentos p
              WHERE m.id=p.id || '_finance' AND p.comercio_id=m.comercio_id
              LIMIT 1)
        WHERE m.centro_resultado IS NULL AND EXISTS (
          SELECT 1 FROM comanda_loja_pagamentos p
          WHERE m.id=p.id || '_finance' AND p.comercio_id=m.comercio_id)''');
    }

    if (names.contains('contas_receber_pagamentos') &&
        names.contains('contas_receber_loja')) {
      await db.rawUpdate('''UPDATE movimentacoes_financeiras AS m
        SET centro_resultado='loja', entidade_origem='conta_receber_loja',
            entidade_origem_id=(SELECT p.conta_id
              FROM contas_receber_pagamentos p
              WHERE (m.id=p.id || '_finance' OR m.id=p.id || '_estorno')
                AND p.comercio_id=m.comercio_id LIMIT 1)
        WHERE m.centro_resultado IS NULL AND EXISTS (
          SELECT 1 FROM contas_receber_pagamentos p
          WHERE (m.id=p.id || '_finance' OR m.id=p.id || '_estorno')
            AND p.comercio_id=m.comercio_id)''');
    }
  }

  static Future<void> _addColumn(
    Database db,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery(
      'PRAGMA table_info(movimentacoes_financeiras)',
    );
    if (!columns.any((row) => row['name'] == column)) {
      await db.execute(
        'ALTER TABLE movimentacoes_financeiras ADD COLUMN $column $definition',
      );
    }
  }
}
