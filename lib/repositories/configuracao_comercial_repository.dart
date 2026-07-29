import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../models/domain/configuracao_comercial.dart';

class ConfiguracaoComercialRepository {
  final Future<Database> Function() _databaseProvider;

  ConfiguracaoComercialRepository({
    Future<Database> Function()? databaseProvider,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseService.instance.database);

  static const _chaves = <String>[
    'cep',
    'rua',
    'numero',
    'complemento',
    'bairro',
    'cidade',
    'estado',
    'ponto_referencia',
    'link_localizacao',
    'latitude',
    'longitude',
  ];

  Future<ConfiguracaoComercial> carregar(String comercioId) async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'configuracoes',
      where: 'comercio_id = ?',
      whereArgs: [comercioId],
    );
    final valores = <String, String>{};
    for (final row in rows) {
      final chave = (row['chave'] as String).replaceFirst('$comercioId.', '');
      if (_chaves.contains(chave)) {
        valores[chave] = row['valor'] as String? ?? '';
      }
    }
    return ConfiguracaoComercial(
      comercioId: comercioId,
      cep: valores['cep'] ?? '',
      rua: valores['rua'] ?? '',
      numero: valores['numero'] ?? '',
      complemento: valores['complemento'] ?? '',
      bairro: valores['bairro'] ?? '',
      cidade: valores['cidade'] ?? '',
      estado: valores['estado'] ?? '',
      pontoReferencia: valores['ponto_referencia'] ?? '',
      linkLocalizacao: valores['link_localizacao'] ?? '',
      latitude: valores['latitude'] ?? '',
      longitude: valores['longitude'] ?? '',
    );
  }

  Future<void> salvar(ConfiguracaoComercial config) async {
    final db = await _databaseProvider();
    final valores = <String, String>{
      'cep': config.cep,
      'rua': config.rua,
      'numero': config.numero,
      'complemento': config.complemento,
      'bairro': config.bairro,
      'cidade': config.cidade,
      'estado': config.estado,
      'ponto_referencia': config.pontoReferencia,
      'link_localizacao': config.linkLocalizacao,
      'latitude': config.latitude,
      'longitude': config.longitude,
    };
    await db.transaction((txn) async {
      for (final item in valores.entries) {
        await txn.insert('configuracoes', {
          'chave': '${config.comercioId}.${item.key}',
          'valor': item.value.trim(),
          'comercio_id': config.comercioId,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }
}
