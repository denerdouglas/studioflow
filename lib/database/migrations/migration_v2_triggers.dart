import 'package:sqflite/sqflite.dart';

abstract final class MigrationV2Triggers {
  static Future<void> executar(Database db) async {
    const tabelas = <String>[
      'clientes',
      'anamneses',
      'profissionais',
      'servicos',
      'agendamentos',
      'estoque',
      'movimentacoes_estoque',
      'manutencoes',
      'movimentacoes_financeiras',
      'comissoes',
      'configuracoes',
      'notificacoes',
    ];
    for (final tabela in tabelas) {
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS vincular_${tabela}_comercio
        AFTER INSERT ON $tabela
        WHEN NEW.comercio_id = 'comercio_legado'
        BEGIN
          UPDATE $tabela
          SET comercio_id = COALESCE(
            (
              SELECT comercio_id
              FROM sessoes
              WHERE ativa = 1
              ORDER BY ultimo_acesso DESC
              LIMIT 1
            ),
            'comercio_legado'
          )
          WHERE rowid = NEW.rowid;
        END
      ''');
    }
  }
}
