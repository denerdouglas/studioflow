import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../models/domain/configuracao_comercio.dart';
import 'acesso_repository.dart';

class ConfiguracoesRepository {
  final DatabaseProvider _databaseProvider;

  ConfiguracoesRepository({DatabaseProvider? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => DatabaseService.instance.database);

  Future<ConfiguracaoComercio> carregar(String comercioId) async {
    final db = await _databaseProvider();
    final comercio = await db.query(
      'comercios',
      where: 'id = ?',
      whereArgs: [comercioId],
      limit: 1,
    );
    if (comercio.isEmpty) {
      throw StateError('Comércio não encontrado.');
    }
    final valores = await db.query(
      'configuracoes',
      where: 'comercio_id = ?',
      whereArgs: [comercioId],
    );
    final mapa = <String, String>{};
    for (final item in valores) {
      final chave = item['chave'] as String;
      mapa[chave.replaceFirst('$comercioId.', '')] =
          item['valor'] as String? ?? '';
    }
    final dados = comercio.first;
    return ConfiguracaoComercio(
      comercioId: comercioId,
      nomeComercio: dados['nome'] as String,
      nomeExibicao: dados['nome_exibicao'] as String,
      telefone: mapa['telefone'] ?? dados['telefone'] as String,
      whatsapp: mapa['whatsapp'] ?? dados['telefone'] as String,
      endereco: mapa['endereco'] ?? '',
      chavePix: mapa['chave_pix'] ?? '',
      horarioAbertura: mapa['horario_abertura'] ?? '08:00',
      horarioFechamento: mapa['horario_fechamento'] ?? '18:00',
      diasFuncionamento: _dias(mapa['dias_funcionamento']),
      duracaoPadraoMinutos: int.tryParse(mapa['duracao_padrao'] ?? '') ?? 60,
      notificacoesAtivas: mapa['notificacoes'] != '0',
      confirmarExclusoes: mapa['confirmar_exclusoes'] != '0',
      permitirGaleriaClientes: mapa['permitir_galeria_clientes'] == '1',
      documentoTipo: dados['documento_tipo'] as String?,
      documento: dados['documento'] as String?,
      inscricaoEstadual: dados['inscricao_estadual'] as String?,
      instagram: dados['instagram'] as String?,
      cep: dados['cep'] as String?,
      numero: dados['numero'] as String?,
      complemento: dados['complemento'] as String?,
      bairro: dados['bairro'] as String?,
      cidade: dados['cidade'] as String?,
      estado: dados['estado'] as String?,
      capaUrl: dados['capa_url'] as String?,
      logoPath: dados['logo_path'] as String?,
      corPrincipal: dados['cor_principal'] as String?,
      corSecundaria: dados['cor_secundaria'] as String?,
      corDestaque: dados['cor_destaque'] as String?,
      temaModo: dados['tema_modo'] as String?,
      temaAutomatico: dados['tema_automatico'] == 1,
    );
  }

  Future<void> salvar(ConfiguracaoComercio configuracao) async {
    final db = await _databaseProvider();
    await db.transaction((txn) async {
      await txn.update(
        'comercios',
        {
          'nome': configuracao.nomeComercio.trim(),
          'nome_exibicao': configuracao.nomeExibicao.trim(),
          'telefone': configuracao.telefone.trim(),
          'whatsapp': configuracao.whatsapp.trim(),
          'instagram': configuracao.instagram?.trim(),
          'documento_tipo': configuracao.documentoTipo?.trim(),
          'documento': configuracao.documento?.trim(),
          'inscricao_estadual': configuracao.inscricaoEstadual?.trim(),
          'cep': configuracao.cep?.trim(),
          'endereco': configuracao.endereco.trim(),
          'numero': configuracao.numero?.trim(),
          'complemento': configuracao.complemento?.trim(),
          'bairro': configuracao.bairro?.trim(),
          'cidade': configuracao.cidade?.trim(),
          'estado': configuracao.estado?.trim(),
          'atualizado_em': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [configuracao.comercioId],
      );
      final valores = <String, String>{
        'telefone': configuracao.telefone.trim(),
        'whatsapp': configuracao.whatsapp.trim(),
        'endereco': configuracao.endereco.trim(),
        'chave_pix': configuracao.chavePix.trim(),
        'horario_abertura': configuracao.horarioAbertura,
        'horario_fechamento': configuracao.horarioFechamento,
        'dias_funcionamento': jsonEncode(
          configuracao.diasFuncionamento.toList()..sort(),
        ),
        'duracao_padrao': configuracao.duracaoPadraoMinutos.toString(),
        'moeda': 'BRL',
        'notificacoes': configuracao.notificacoesAtivas ? '1' : '0',
        'confirmar_exclusoes': configuracao.confirmarExclusoes ? '1' : '0',
        'permitir_galeria_clientes': configuracao.permitirGaleriaClientes
            ? '1'
            : '0',
      };
      for (final item in valores.entries) {
        await txn.insert('configuracoes', {
          'chave': '${configuracao.comercioId}.${item.key}',
          'valor': item.value,
          'comercio_id': configuracao.comercioId,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  static Set<int> _dias(String? valor) {
    if (valor == null || valor.isEmpty) {
      return {1, 2, 3, 4, 5, 6};
    }
    try {
      return (jsonDecode(valor) as List<dynamic>)
          .map((item) => (item as num).toInt())
          .toSet();
    } on FormatException {
      return {1, 2, 3, 4, 5, 6};
    }
  }
}
