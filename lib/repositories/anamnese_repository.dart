import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';
import '../models/domain/anamnese.dart';
import '../services/session_controller.dart';

class AnamneseRepository {
  final Future<Database> Function() _databaseProvider;
  final String? _comercioInformado;
  final String? _usuarioInformado;

  AnamneseRepository({
    Future<Database> Function()? databaseProvider,
    String? comercioId,
    String? usuarioId,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseService.instance.database),
       _comercioInformado = comercioId,
       _usuarioInformado = usuarioId;

  String get _comercioId =>
      _comercioInformado ?? SessionController.instance.usuario!.comercioId;
  String get _usuarioId =>
      _usuarioInformado ?? SessionController.instance.usuario!.id;

  Future<AnamneseRegistro?> atual(String clienteId) async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'anamneses',
      where: 'comercio_id = ? AND cliente_id = ? AND ativa = 1',
      whereArgs: [_comercioId, clienteId],
      orderBy: 'versao DESC, data_atualizacao DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : AnamneseRegistro.doMapa(rows.first);
  }

  Future<List<AnamneseRegistro>> historico(String clienteId) async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'anamneses',
      where: 'comercio_id = ? AND cliente_id = ?',
      whereArgs: [_comercioId, clienteId],
      orderBy: 'versao DESC, data_atualizacao DESC',
    );
    return rows.map(AnamneseRegistro.doMapa).toList();
  }

  Future<AnamneseRegistro> salvar(AnamneseRegistro ficha) async {
    if (ficha.clienteId.trim().isEmpty) {
      throw ArgumentError('Cliente obrigatório.');
    }
    if (!ficha.clienteConfirmouInformacoes) {
      throw StateError('A cliente precisa confirmar as informações.');
    }
    if (!ficha.autorizouProcedimento) {
      throw StateError('A autorização do procedimento é obrigatória.');
    }
    if (ficha.assinaturaCliente.trim().length < 3) {
      throw StateError('Informe o nome completo da cliente como assinatura.');
    }
    if ((ficha.respostas['possui_alergias'] ?? false) &&
        ficha.descricaoAlergias.trim().isEmpty) {
      throw StateError('Descreva as alergias informadas.');
    }
    if ((ficha.respostas['usa_medicamentos'] ?? false) &&
        ficha.medicamentos.trim().isEmpty) {
      throw StateError('Informe os medicamentos utilizados.');
    }
    if ((ficha.respostas['possui_problemas_pele'] ?? false) &&
        ficha.problemasPele.trim().isEmpty) {
      throw StateError('Descreva os problemas de pele informados.');
    }

    final db = await _databaseProvider();
    return db.transaction((txn) async {
      final cliente = await txn.query(
        'clientes',
        columns: ['id'],
        where: 'id = ? AND comercio_id = ? AND ativo = 1',
        whereArgs: [ficha.clienteId, _comercioId],
        limit: 1,
      );
      if (cliente.isEmpty) throw StateError('Cliente não encontrada.');

      final ultima = await txn.rawQuery(
        'SELECT MAX(versao) AS versao FROM anamneses '
        'WHERE comercio_id = ? AND cliente_id = ?',
        [_comercioId, ficha.clienteId],
      );
      final versao = ((ultima.first['versao'] as num?)?.toInt() ?? 0) + 1;
      final agora = DateTime.now().toUtc();
      await txn.update(
        'anamneses',
        {'ativa': 0, 'data_atualizacao': agora.toIso8601String()},
        where: 'comercio_id = ? AND cliente_id = ? AND ativa = 1',
        whereArgs: [_comercioId, ficha.clienteId],
      );
      final salva = AnamneseRegistro(
        id: 'ana_${_comercioId}_${agora.microsecondsSinceEpoch}',
        clienteId: ficha.clienteId,
        comercioId: _comercioId,
        tipoFicha: ficha.tipoFicha,
        versao: versao,
        ativa: true,
        respostas: ficha.respostas,
        descricaoAlergias: ficha.descricaoAlergias,
        medicamentos: ficha.medicamentos,
        problemasPele: ficha.problemasPele,
        formatoPreferido: ficha.formatoPreferido,
        comprimentoPreferido: ficha.comprimentoPreferido,
        restricoes: ficha.restricoes,
        observacoes: ficha.observacoes,
        clienteConfirmouInformacoes: ficha.clienteConfirmouInformacoes,
        autorizouProcedimento: ficha.autorizouProcedimento,
        assinaturaCliente: ficha.assinaturaCliente,
        termoVersao: ficha.termoVersao,
        dataCriacao: agora,
        dataAtualizacao: agora,
        criadoPorId: _usuarioId,
        atualizadoPorId: _usuarioId,
        agendamentoId: ficha.agendamentoId,
      );
      await txn.insert('anamneses', salva.paraMapa());
      return salva;
    });
  }
}
