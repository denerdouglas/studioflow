import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../models/domain/aparencia.dart';

class AparenciaRepository {
  final Future<Database> Function() _databaseProvider;

  AparenciaRepository({Future<Database> Function()? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => DatabaseService.instance.database);

  Future<ConfiguracaoAparencia> carregar(String comercioId) async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'comercios',
      columns: [
        'logo_path',
        'cor_principal',
        'cor_secundaria',
        'cor_destaque',
        'tema_modo',
        'tema_automatico',
      ],
      where: 'id = ?',
      whereArgs: [comercioId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Estabelecimento não encontrado.');
    final row = rows.first;
    return ConfiguracaoAparencia(
      comercioId: comercioId,
      logoPath: row['logo_path'] as String? ?? '',
      corPrincipal: row['cor_principal'] as String? ?? '#70569A',
      corSecundaria: row['cor_secundaria'] as String? ?? '#8B5CF6',
      corDestaque: row['cor_destaque'] as String? ?? '#D9C7F2',
      temaModo: row['tema_modo'] as String? ?? 'claro',
      temaAutomatico: (row['tema_automatico'] as num? ?? 1) == 1,
    );
  }

  Future<void> salvar(ConfiguracaoAparencia config) async {
    for (final cor in [
      config.corPrincipal,
      config.corSecundaria,
      config.corDestaque,
    ]) {
      if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(cor.trim())) {
        throw const FormatException('Use cores no formato #RRGGBB.');
      }
    }
    final db = await _databaseProvider();
    await db.update(
      'comercios',
      {
        'logo_path': config.logoPath.trim(),
        'cor_principal': config.corPrincipal.toUpperCase(),
        'cor_secundaria': config.corSecundaria.toUpperCase(),
        'cor_destaque': config.corDestaque.toUpperCase(),
        'tema_modo': config.temaModo,
        'tema_automatico': config.temaAutomatico ? 1 : 0,
        'atualizado_em': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [config.comercioId],
    );
  }
}
