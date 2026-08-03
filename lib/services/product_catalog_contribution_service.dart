import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/utils/id_generator.dart';
import '../models/domain/acesso.dart';

abstract final class ProductCatalogContributionService {
  static Future<void> enqueue(
    DatabaseExecutor db, {
    required UsuarioAcesso user,
    required String barcode,
    required String name,
    String? brand,
    String? description,
    String? category,
    String? imageUrl,
    String? unit,
    String source = 'manual',
  }) async {
    if (barcode.isEmpty || name.trim().isEmpty) return;
    final existing = await db.query(
      'catalogo_sugestoes',
      columns: ['id'],
      where: "comercio_id = ? AND gtin = ? AND status = 'pendente'",
      whereArgs: [user.comercioId, barcode],
      limit: 1,
    );
    if (existing.isNotEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final id = 'sug_${IdGenerator.temporal()}';
    final publicData = <String, Object?>{
      'barcode': barcode,
      'gtin': barcode,
      'name': name.trim(),
      'brand': _clean(brand),
      'description': _clean(description),
      'category': _clean(category),
      'imageUrl': _https(imageUrl),
      'unit': _clean(unit),
      'source': source == 'external' ? 'external' : 'studioflow',
    };
    await db.insert('catalogo_sugestoes', {
      'id': id,
      'comercio_id': user.comercioId,
      'usuario_id': user.id,
      'gtin': barcode,
      'dados_json': jsonEncode(publicData),
      'fonte_informada': source,
      'consentimento': 1,
      'status': 'pendente',
      'criado_em': now,
    });
    await db.insert('fila_sincronizacao', {
      'id': 'sync_$id',
      'comercio_id': user.comercioId,
      'unidade_id': null,
      'entidade': 'catalogo_sugestao',
      'entidade_id': id,
      'operacao': 'criar',
      'payload_json': jsonEncode(publicData),
      'versao_local': 1,
      'status': 'pendente',
      'tentativas': 0,
      'criada_em': now,
      'atualizada_em': now,
    });
  }

  static String? _clean(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String? _https(String? value) {
    final uri = value == null ? null : Uri.tryParse(value.trim());
    return uri?.scheme == 'https' ? uri.toString() : null;
  }
}
