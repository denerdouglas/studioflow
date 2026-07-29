import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../services/session_controller.dart';

class ClienteRegistro {
  final String id;
  final String nome;
  final String whatsapp;
  final String telefone;
  final String email;
  final DateTime? dataNascimento;
  final String profissional;
  final String ultimoServico;
  final double totalGasto;
  final int totalAtendimentos;
  final String observacoes;
  final DateTime dataCadastro;
  final bool consentimentoWhatsapp;
  final bool consentimentoMarketing;

  const ClienteRegistro({
    required this.id,
    required this.nome,
    required this.whatsapp,
    this.telefone = '',
    this.email = '',
    this.dataNascimento,
    required this.profissional,
    required this.ultimoServico,
    required this.totalGasto,
    required this.totalAtendimentos,
    required this.observacoes,
    required this.dataCadastro,
    this.consentimentoWhatsapp = false,
    this.consentimentoMarketing = false,
  });

  Map<String, Object?> paraMapa() => {
    'id': id,
    'nome': nome.trim(),
    'whatsapp': whatsapp.trim(),
    'telefone': telefone.trim(),
    'email': email.trim().isEmpty ? null : email.trim(),
    'data_nascimento': dataNascimento?.toIso8601String(),
    'profissional_principal_id': profissional,
    'observacoes': observacoes.trim(),
    'ativo': 1,
    'data_cadastro': dataCadastro.toIso8601String(),
    'total_atendimentos': totalAtendimentos,
    'total_gasto': totalGasto,
    'consentimento_whatsapp': consentimentoWhatsapp ? 1 : 0,
    'consentimento_marketing': consentimentoMarketing ? 1 : 0,
    'atualizado_em': DateTime.now().toUtc().toIso8601String(),
  };

  factory ClienteRegistro.doMapa(Map<String, Object?> mapa) => ClienteRegistro(
    id: mapa['id'] as String,
    nome: mapa['nome'] as String,
    whatsapp: mapa['whatsapp'] as String,
    telefone: mapa['telefone'] as String? ?? '',
    email: mapa['email'] as String? ?? '',
    dataNascimento: DateTime.tryParse(mapa['data_nascimento'] as String? ?? ''),
    profissional:
        mapa['profissional_principal_id'] as String? ??
        'Sem profissional definida',
    ultimoServico: 'Nenhum atendimento',
    totalGasto: (mapa['total_gasto'] as num? ?? 0).toDouble(),
    totalAtendimentos: (mapa['total_atendimentos'] as num? ?? 0).toInt(),
    observacoes: mapa['observacoes'] as String? ?? '',
    dataCadastro:
        DateTime.tryParse(mapa['data_cadastro'] as String? ?? '') ??
        DateTime.now(),
    consentimentoWhatsapp: (mapa['consentimento_whatsapp'] as int? ?? 0) == 1,
    consentimentoMarketing: (mapa['consentimento_marketing'] as int? ?? 0) == 1,
  );

  ClienteRegistro copiarCom({
    String? nome,
    String? whatsapp,
    String? telefone,
    String? email,
    DateTime? dataNascimento,
    String? profissional,
    String? ultimoServico,
    double? totalGasto,
    int? totalAtendimentos,
    String? observacoes,
    bool? consentimentoWhatsapp,
    bool? consentimentoMarketing,
  }) => ClienteRegistro(
    id: id,
    nome: nome ?? this.nome,
    whatsapp: whatsapp ?? this.whatsapp,
    telefone: telefone ?? this.telefone,
    email: email ?? this.email,
    dataNascimento: dataNascimento ?? this.dataNascimento,
    profissional: profissional ?? this.profissional,
    ultimoServico: ultimoServico ?? this.ultimoServico,
    totalGasto: totalGasto ?? this.totalGasto,
    totalAtendimentos: totalAtendimentos ?? this.totalAtendimentos,
    observacoes: observacoes ?? this.observacoes,
    dataCadastro: dataCadastro,
    consentimentoWhatsapp: consentimentoWhatsapp ?? this.consentimentoWhatsapp,
    consentimentoMarketing:
        consentimentoMarketing ?? this.consentimentoMarketing,
  );
}

class ClienteRepository {
  final DatabaseService _databaseService;
  ClienteRepository({DatabaseService? databaseService})
    : _databaseService = databaseService ?? DatabaseService.instance;
  String get _comercioId => SessionController.instance.usuario!.comercioId;

  Future<List<ClienteRegistro>> listar() async {
    final db = await _databaseService.database;
    final registros = await db.query(
      'clientes',
      where: 'ativo = ? AND comercio_id = ?',
      whereArgs: [1, _comercioId],
      orderBy: 'nome COLLATE NOCASE ASC',
    );
    return registros.map(ClienteRegistro.doMapa).toList();
  }

  Future<ClienteRegistro?> buscarPorId(String clienteId) async {
    final db = await _databaseService.database;
    final registros = await db.query(
      'clientes',
      where: 'id = ? AND ativo = ? AND comercio_id = ?',
      whereArgs: [clienteId, 1, _comercioId],
      limit: 1,
    );
    return registros.isEmpty ? null : ClienteRegistro.doMapa(registros.first);
  }

  Future<void> inserir(ClienteRegistro cliente) async {
    final db = await _databaseService.database;
    if (await existeWhatsapp(cliente.whatsapp)) {
      throw StateError('Já existe um cliente com este WhatsApp.');
    }
    await db.insert('clientes', {
      ...cliente.paraMapa(),
      'comercio_id': _comercioId,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<void> atualizar(ClienteRegistro cliente) async {
    final db = await _databaseService.database;
    final duplicado = await db.query(
      'clientes',
      columns: ['id'],
      where: 'whatsapp = ? AND ativo = 1 AND comercio_id = ? AND id != ?',
      whereArgs: [cliente.whatsapp, _comercioId, cliente.id],
      limit: 1,
    );
    if (duplicado.isNotEmpty) {
      throw StateError('Já existe outro cliente com este WhatsApp.');
    }
    final alterados = await db.update(
      'clientes',
      cliente.paraMapa(),
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [cliente.id, _comercioId],
    );
    if (alterados == 0) throw StateError('Cliente não encontrado.');
  }

  Future<void> excluir(String clienteId) async {
    final db = await _databaseService.database;
    await db.update(
      'clientes',
      {'ativo': 0, 'atualizado_em': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [clienteId, _comercioId],
    );
  }

  Future<bool> existeWhatsapp(String whatsapp) async {
    final db = await _databaseService.database;
    final resultado = await db.query(
      'clientes',
      columns: ['id'],
      where: 'whatsapp = ? AND ativo = ? AND comercio_id = ?',
      whereArgs: [whatsapp.trim(), 1, _comercioId],
      limit: 1,
    );
    return resultado.isNotEmpty;
  }

  Future<int> quantidadeClientes() async {
    final db = await _databaseService.database;
    final resultado = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM clientes WHERE ativo = 1 AND comercio_id = ?',
      [_comercioId],
    );
    return (resultado.first['total'] as int?) ?? 0;
  }

  Future<double> faturamentoTotal() async {
    final db = await _databaseService.database;
    final resultado = await db.rawQuery(
      'SELECT SUM(total_gasto) AS total FROM clientes WHERE ativo = 1 AND comercio_id = ?',
      [_comercioId],
    );
    return (resultado.first['total'] as num? ?? 0).toDouble();
  }
}
