import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/security/password_hasher.dart';
import '../core/utils/id_generator.dart';
import '../models/domain/acesso.dart';
import 'acesso_repository.dart';

class SolicitacaoEquipe {
  final String id;
  final String accountId;
  final String nome;
  final String login;
  final String telefone;
  final String status;

  const SolicitacaoEquipe({
    required this.id,
    required this.accountId,
    required this.nome,
    required this.login,
    required this.telefone,
    required this.status,
  });
}

class CapacidadeEquipe {
  final int utilizados;
  final int capacidade;

  const CapacidadeEquipe(this.utilizados, this.capacidade);

  bool get disponivel => utilizados < capacidade;
}

class OpcaoEquipe {
  final String id;
  final String nome;
  final double? comissao;

  const OpcaoEquipe(this.id, this.nome, [this.comissao]);
}

class EquipeDetalhe {
  final UsuarioGerenciavel usuario;
  final String unidade;
  final Set<String> modalidadeIds;
  final Map<String, double?> servicos;
  final Map<String, double> comissoesEfetivas;

  const EquipeDetalhe({
    required this.usuario,
    required this.unidade,
    required this.modalidadeIds,
    required this.servicos,
    required this.comissoesEfetivas,
  });
}

class EquipeRepository {
  final AcessoRepository _acesso;

  EquipeRepository({AcessoRepository? acesso})
    : _acesso = acesso ?? AcessoRepository();

  Future<Database> get _db => _acesso.database;

  Future<List<OpcaoEquipe>> listarModalidades(String businessId) async {
    final rows = await (await _db).query(
      'modalidades_estabelecimento',
      columns: ['id', 'nome'],
      where: 'comercio_id=? AND ativa=1',
      whereArgs: [businessId],
      orderBy: 'ordem,nome COLLATE NOCASE',
    );
    return rows
        .map((row) => OpcaoEquipe(row['id'] as String, row['nome'] as String))
        .toList();
  }

  Future<List<OpcaoEquipe>> listarServicos(String businessId) async {
    final rows = await (await _db).query(
      'servicos',
      columns: ['id', 'nome', 'comissao_percentual'],
      where: 'comercio_id=? AND ativo=1',
      whereArgs: [businessId],
      orderBy: 'nome COLLATE NOCASE',
    );
    return rows
        .map(
          (row) => OpcaoEquipe(
            row['id'] as String,
            row['nome'] as String,
            (row['comissao_percentual'] as num?)?.toDouble(),
          ),
        )
        .toList();
  }

  Future<EquipeDetalhe> detalhe(UsuarioGerenciavel usuario) async {
    final db = await _db;
    final business = await db.query(
      'comercios',
      columns: ['nome_exibicao'],
      where: 'id=?',
      whereArgs: [usuario.comercioId],
      limit: 1,
    );
    final areas = usuario.profissionalId == null
        ? const <Map<String, Object?>>[]
        : await db.query(
            'modalidade_profissionais',
            columns: ['modalidade_id'],
            where: 'comercio_id=? AND profissional_id=? AND ativo=1',
            whereArgs: [usuario.comercioId, usuario.profissionalId],
          );
    final services = usuario.profissionalId == null
        ? const <Map<String, Object?>>[]
        : await db.rawQuery(
            '''SELECT ps.servico_id, ps.comissao_percentual_override,
                      s.comissao_percentual, p.percentual_comissao
               FROM profissional_servicos ps
               JOIN servicos s ON s.id=ps.servico_id AND s.comercio_id=?
               JOIN profissionais p ON p.id=ps.profissional_id
               WHERE ps.profissional_id=? AND COALESCE(ps.ativo,1)=1''',
            [usuario.comercioId, usuario.profissionalId],
          );
    final serviceMap = <String, double?>{};
    final effective = <String, double>{};
    for (final row in services) {
      final id = row['servico_id'] as String;
      final override = (row['comissao_percentual_override'] as num?)
          ?.toDouble();
      serviceMap[id] = override;
      effective[id] =
          override ??
          (row['comissao_percentual'] as num?)?.toDouble() ??
          (row['percentual_comissao'] as num?)?.toDouble() ??
          0;
    }
    return EquipeDetalhe(
      usuario: usuario,
      unidade: business.isEmpty
          ? usuario.comercioId
          : business.first['nome_exibicao'] as String,
      modalidadeIds: areas.map((row) => row['modalidade_id'] as String).toSet(),
      servicos: serviceMap,
      comissoesEfetivas: effective,
    );
  }

  Future<List<UsuarioAcesso>> minhasUnidades(UsuarioAcesso atual) async {
    final db = await _db;
    final account = await db.query(
      'business_memberships',
      columns: ['account_id'],
      where: 'usuario_id=? AND business_id=? AND status=?',
      whereArgs: [atual.id, atual.comercioId, 'active'],
      limit: 1,
    );
    if (account.isEmpty) return [atual];
    final rows = await db.query(
      'business_memberships',
      columns: ['usuario_id'],
      where: 'account_id=? AND status=?',
      whereArgs: [account.first['account_id'], 'active'],
    );
    final result = <UsuarioAcesso>[];
    for (final row in rows) {
      final id = row['usuario_id'] as String?;
      if (id == null) continue;
      final user = await _acesso.carregarUsuario(id);
      if (user != null && user.ativo) result.add(user);
    }
    return result;
  }

  Future<String> codigoPublico(String businessId) async {
    final rows = await (await _db).query(
      'business_public_codes',
      columns: ['code'],
      where: 'business_id=? AND ativo=1',
      whereArgs: [businessId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Código público indisponível.');
    return rows.first['code'] as String;
  }

  Future<Map<String, String>?> localizarUnidade(String codigo) async {
    final rows = await (await _db).rawQuery(
      '''SELECT c.id, c.nome_exibicao FROM business_public_codes p
         JOIN comercios c ON c.id=p.business_id
         WHERE UPPER(p.code)=UPPER(?) AND p.ativo=1 AND c.ativo=1 LIMIT 1''',
      [codigo.trim()],
    );
    if (rows.isEmpty) return null;
    return {
      'id': rows.first['id'] as String,
      'nome': rows.first['nome_exibicao'] as String,
    };
  }

  Future<void> solicitarAcesso({
    required String businessId,
    required String nome,
    required String telefone,
    required String login,
    required String senha,
  }) async {
    if (senha.length < 6) throw const FormatException('Senha muito curta.');
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    final normalized = login.trim().toLowerCase();
    final existing = await db.query(
      'accounts',
      where: 'LOWER(login)=?',
      whereArgs: [normalized],
      limit: 1,
    );
    final accountId = existing.isEmpty
        ? 'acc_${IdGenerator.temporal()}'
        : existing.first['id'] as String;
    final protected = PasswordHasher.criar(senha);
    await db.transaction((txn) async {
      if (existing.isEmpty) {
        await txn.insert('accounts', {
          'id': accountId,
          'login': normalized,
          'nome': nome.trim(),
          'telefone': telefone.trim(),
          'senha_hash': protected.hash,
          'senha_salt': protected.salt,
          'ativo': 1,
          'criado_em': now,
          'atualizado_em': now,
        });
      }
      final duplicate = await txn.query(
        'business_membership_requests',
        where: 'account_id=? AND business_id=? AND status IN (?,?)',
        whereArgs: [accountId, businessId, 'pending', 'pending_billing'],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        throw StateError('Já existe uma solicitação aguardando aprovação.');
      }
      await txn.insert('business_membership_requests', {
        'id': 'req_${IdGenerator.temporal()}',
        'account_id': accountId,
        'business_id': businessId,
        'status': 'pending',
        'solicitado_em': now,
      });
    });
  }

  Future<List<SolicitacaoEquipe>> listarSolicitacoes(String businessId) async {
    final rows = await (await _db).rawQuery(
      '''SELECT r.id, r.account_id, r.status, a.nome, a.login, a.telefone
         FROM business_membership_requests r JOIN accounts a ON a.id=r.account_id
         WHERE r.business_id=? AND r.status IN ('pending','pending_billing')
         ORDER BY r.solicitado_em''',
      [businessId],
    );
    return rows
        .map(
          (row) => SolicitacaoEquipe(
            id: row['id'] as String,
            accountId: row['account_id'] as String,
            nome: row['nome'] as String,
            login: row['login'] as String,
            telefone: row['telefone'] as String,
            status: row['status'] as String,
          ),
        )
        .toList();
  }

  Future<CapacidadeEquipe> capacidade(String businessId) async {
    final db = await _db;
    final owner = await db.rawQuery(
      '''SELECT account_id FROM business_memberships
         WHERE business_id=? AND role='owner' AND status='active' LIMIT 1''',
      [businessId],
    );
    final accountId = owner.isEmpty
        ? null
        : owner.first['account_id'] as String;
    final entitlement = accountId == null
        ? const <Map<String, Object?>>[]
        : await db.query(
            'account_entitlements',
            columns: ['capacidade_colaboradores'],
            where: 'account_id=?',
            whereArgs: [accountId],
            limit: 1,
          );
    final limit = entitlement.isEmpty
        ? 3
        : (entitlement.first['capacidade_colaboradores'] as num).toInt();
    final count =
        Sqflite.firstIntValue(
          await db.rawQuery(
            '''SELECT COUNT(*) FROM business_memberships
               WHERE business_id=? AND status='active' AND role!='owner' ''',
            [businessId],
          ),
        ) ??
        0;
    return CapacidadeEquipe(count, limit);
  }

  Future<void> recusar({
    required UsuarioAcesso ator,
    required String solicitacaoId,
  }) async {
    if (ator.funcao != FuncaoUsuario.dono) {
      throw StateError('Somente a proprietária pode recusar solicitações.');
    }
    await (await _db).update(
      'business_membership_requests',
      {
        'status': 'rejected',
        'revisado_em': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id=? AND business_id=? AND status IN (?,?)',
      whereArgs: [solicitacaoId, ator.comercioId, 'pending', 'pending_billing'],
    );
  }

  Future<void> aprovar({
    required UsuarioAcesso ator,
    required String solicitacaoId,
    required FuncaoUsuario funcao,
    required Set<ModuloPermissao> permissoes,
    required Set<AcaoPermissao> acoes,
    Set<String> modalidadeIds = const {},
    Map<String, double?> servicos = const {},
  }) async {
    if (ator.funcao != FuncaoUsuario.dono) {
      throw StateError('Somente a proprietária pode aprovar solicitações.');
    }
    if (funcao == FuncaoUsuario.dono) {
      throw StateError('Solicitações não podem receber perfil proprietário.');
    }
    final db = await _db;
    final rows = await db.rawQuery(
      '''SELECT r.*, a.nome, a.login, a.telefone, a.senha_hash, a.senha_salt
         FROM business_membership_requests r JOIN accounts a ON a.id=r.account_id
         WHERE r.id=? AND r.business_id=? AND r.status IN ('pending','pending_billing') LIMIT 1''',
      [solicitacaoId, ator.comercioId],
    );
    if (rows.isEmpty) throw StateError('Solicitação não encontrada.');
    final capacity = await capacidade(ator.comercioId);
    if (!capacity.disponivel) {
      await db.update(
        'business_membership_requests',
        {'status': 'pending_billing'},
        where: 'id=?',
        whereArgs: [solicitacaoId],
      );
      throw StateError('Limite de colaboradores atingido. Ajuste o plano.');
    }
    final row = rows.first;
    final temporaryPassword = 'Temp@${IdGenerator.temporal()}';
    await _acesso.salvarUsuario(
      ator: ator,
      nome: row['nome'] as String,
      telefone: row['telefone'] as String,
      emailLogin: row['login'] as String,
      senha: temporaryPassword,
      funcao: funcao,
      ativo: true,
      permissoes: permissoes,
      acoes: acoes,
    );
    final users = await db.query(
      'usuarios',
      where: 'comercio_id=? AND LOWER(email_login)=LOWER(?)',
      whereArgs: [ator.comercioId, row['login']],
      limit: 1,
    );
    final user = users.single;
    await db.transaction((txn) async {
      if (row['senha_hash'] != null) {
        await txn.update(
          'usuarios',
          {'senha_hash': row['senha_hash'], 'senha_salt': row['senha_salt']},
          where: 'id=?',
          whereArgs: [user['id']],
        );
      }
      await txn.insert('business_memberships', {
        'id': 'mem_${IdGenerator.temporal()}',
        'account_id': row['account_id'],
        'business_id': ator.comercioId,
        'usuario_id': user['id'],
        'profissional_id': user['profissional_id'],
        'role': funcao == FuncaoUsuario.gerente ? 'manager' : 'collaborator',
        'permissions_json': jsonEncode({
          'modules': permissoes.map((e) => e.name).toList(),
          'actions': acoes.map((e) => e.name).toList(),
        }),
        'status': 'active',
        'principal': 0,
        'criado_em': DateTime.now().toUtc().toIso8601String(),
        'atualizado_em': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      for (final id in modalidadeIds) {
        await txn.insert('modalidade_profissionais', {
          'comercio_id': ator.comercioId,
          'modalidade_id': id,
          'profissional_id': user['profissional_id'],
          'ativo': 1,
          'atualizado_em': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final entry in servicos.entries) {
        await txn.insert('profissional_servicos', {
          'profissional_id': user['profissional_id'],
          'servico_id': entry.key,
          'business_id': ator.comercioId,
          'ativo': 1,
          'comissao_percentual_override': entry.value,
          'atualizado_por': ator.id,
          'criado_em': DateTime.now().toUtc().toIso8601String(),
          'atualizado_em': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.update(
        'business_membership_requests',
        {
          'status': 'approved',
          'role_aprovada': funcao.name,
          'permissions_json': jsonEncode({
            'modules': permissoes.map((e) => e.name).toList(),
            'actions': acoes.map((e) => e.name).toList(),
          }),
          'revisado_em': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id=?',
        whereArgs: [solicitacaoId],
      );
    });
  }

  Future<void> editar({
    required UsuarioAcesso ator,
    required UsuarioGerenciavel usuario,
    required FuncaoUsuario funcao,
    required Set<ModuloPermissao> permissoes,
    required Set<AcaoPermissao> acoes,
    required Set<String> modalidadeIds,
    required Map<String, double?> servicos,
    bool confirmarRemocaoComAgenda = false,
  }) async {
    if (ator.comercioId != usuario.comercioId) {
      throw StateError('Colaborador pertence a outra unidade.');
    }
    if (funcao == FuncaoUsuario.dono) {
      throw StateError('Não é permitido transformar alguém em proprietário.');
    }
    if (ator.id == usuario.id && ator.funcao == FuncaoUsuario.gerente) {
      throw StateError('Gerente não pode alterar o próprio cargo.');
    }
    if (ator.funcao != FuncaoUsuario.dono) {
      throw StateError('Somente a proprietária pode editar a equipe.');
    }
    final db = await _db;
    final profissionalId = usuario.profissionalId;
    if (profissionalId == null) throw StateError('Profissional não vinculado.');
    final atuais = await db.query(
      'profissional_servicos',
      columns: ['servico_id'],
      where: 'profissional_id=? AND business_id=? AND COALESCE(ativo,1)=1',
      whereArgs: [profissionalId, usuario.comercioId],
    );
    final removidos = atuais
        .map((row) => row['servico_id'] as String)
        .where((id) => !servicos.containsKey(id))
        .toList();
    if (removidos.isNotEmpty && !confirmarRemocaoComAgenda) {
      final marks = List.filled(removidos.length, '?').join(',');
      final future =
          Sqflite.firstIntValue(
            await db.rawQuery(
              '''SELECT COUNT(*) FROM agendamentos
                 WHERE business_id=? AND profissional_id=?
                   AND servico_id IN ($marks) AND inicio>?
                   AND status NOT IN ('cancelado','concluido') AND deleted_at IS NULL''',
              [
                usuario.comercioId,
                profissionalId,
                ...removidos,
                DateTime.now().toUtc().toIso8601String(),
              ],
            ),
          ) ??
          0;
      if (future > 0) {
        throw StateError(
          'Existem $future agendamentos futuros nesses serviços. Confirme a remoção.',
        );
      }
    }
    await _acesso.salvarUsuario(
      ator: ator,
      usuarioId: usuario.id,
      nome: usuario.nome,
      telefone: usuario.telefone,
      emailLogin: usuario.emailLogin,
      senha: null,
      funcao: funcao,
      ativo: usuario.ativo,
      permissoes: permissoes,
      acoes: acoes,
    );
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(
        'business_memberships',
        {
          'role': funcao == FuncaoUsuario.gerente ? 'manager' : 'collaborator',
          'permissions_json': _permissionsJson(permissoes, acoes),
          'atualizado_em': now,
        },
        where: 'business_id=? AND usuario_id=?',
        whereArgs: [usuario.comercioId, usuario.id],
      );
      await txn.update(
        'modalidade_profissionais',
        {'ativo': 0, 'atualizado_em': now},
        where: 'comercio_id=? AND profissional_id=?',
        whereArgs: [usuario.comercioId, profissionalId],
      );
      for (final id in modalidadeIds) {
        await txn.insert('modalidade_profissionais', {
          'comercio_id': usuario.comercioId,
          'modalidade_id': id,
          'profissional_id': profissionalId,
          'ativo': 1,
          'atualizado_em': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.update(
        'profissional_servicos',
        {'ativo': 0, 'atualizado_em': now, 'atualizado_por': ator.id},
        where: 'business_id=? AND profissional_id=?',
        whereArgs: [usuario.comercioId, profissionalId],
      );
      for (final entry in servicos.entries) {
        await txn.insert('profissional_servicos', {
          'profissional_id': profissionalId,
          'servico_id': entry.key,
          'business_id': usuario.comercioId,
          'ativo': 1,
          'comissao_percentual_override': entry.value,
          'atualizado_por': ator.id,
          'criado_em': now,
          'atualizado_em': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<int> agendamentosFuturos(UsuarioGerenciavel usuario) async {
    if (usuario.profissionalId == null) return 0;
    return Sqflite.firstIntValue(
          await (await _db).rawQuery(
            '''SELECT COUNT(*) FROM agendamentos
               WHERE business_id=? AND profissional_id=? AND inicio>?
                 AND status NOT IN ('cancelado','concluido') AND deleted_at IS NULL''',
            [
              usuario.comercioId,
              usuario.profissionalId,
              DateTime.now().toUtc().toIso8601String(),
            ],
          ),
        ) ??
        0;
  }

  Future<void> alterarAtivo({
    required UsuarioAcesso ator,
    required UsuarioGerenciavel usuario,
    required bool ativo,
  }) async {
    if (ator.funcao != FuncaoUsuario.dono ||
        ator.comercioId != usuario.comercioId ||
        usuario.funcao == FuncaoUsuario.dono) {
      throw StateError('Operação não permitida.');
    }
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(
        'business_memberships',
        {'status': ativo ? 'active' : 'inactive', 'atualizado_em': now},
        where: 'business_id=? AND usuario_id=?',
        whereArgs: [usuario.comercioId, usuario.id],
      );
      await txn.update(
        'usuarios',
        {'ativo': ativo ? 1 : 0, 'atualizado_em': now},
        where: 'id=? AND comercio_id=?',
        whereArgs: [usuario.id, usuario.comercioId],
      );
      if (usuario.profissionalId != null) {
        await txn.update(
          'profissionais',
          {'ativo': ativo ? 1 : 0},
          where: 'id=?',
          whereArgs: [usuario.profissionalId],
        );
      }
      if (!ativo) {
        await txn.update(
          'sessoes',
          {'ativa': 0},
          where: 'usuario_id=? AND comercio_id=?',
          whereArgs: [usuario.id, usuario.comercioId],
        );
      }
    });
  }

  String _permissionsJson(
    Set<ModuloPermissao> permissoes,
    Set<AcaoPermissao> acoes,
  ) => jsonEncode({
    'modules': permissoes.map((e) => e.name).toList(),
    'actions': acoes.map((e) => e.name).toList(),
  });
}
