import 'package:sqflite/sqflite.dart';

class MigrationV21 {
  static Future<void> executar(Database db) async {
    final colunas = <String, String>{
      'documento': 'TEXT',
      'rg': 'TEXT',
      'data_nascimento': 'TEXT',
      'chave_pix': 'TEXT',
      'banco': 'TEXT',
      'cor_agenda': 'TEXT',
      'unidade_id': 'TEXT',
      'sexo': 'TEXT',
      'observacoes': 'TEXT',
      'contato_emergencia': 'TEXT',
    };

    for (final entry in colunas.entries) {
      if (!await _colunaExiste(db, 'profissionais', entry.key)) {
        await db.execute(
          'ALTER TABLE profissionais ADD COLUMN ${entry.key} ${entry.value}',
        );
      }
    }
  }

  static Future<bool> _colunaExiste(
    Database db,
    String tabela,
    String coluna,
  ) async {
    final colunas = await db.rawQuery('PRAGMA table_info($tabela)');
    return colunas.any((c) => c['name'] == coluna);
  }
}
