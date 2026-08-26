import 'package:sqflite/sqflite.dart';

import '../core/security/password_hasher.dart';
import '../core/utils/id_generator.dart';
import '../core/utils/booking_slug.dart';
import '../database/database_service.dart';
import '../database/migrations/migration_v2_impl.dart';
import '../models/domain/acesso.dart';
import '../models/domain/business_profile.dart';

typedef DatabaseProvider = Future<Database> Function();

class AcessoRepository {
  final DatabaseProvider _databaseProvider;

  AcessoRepository({DatabaseProvider? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => DatabaseService.instance.database);

  Future<Database> get database => _databaseProvider();

  Future<UsuarioAcesso> cadastrarComercio(
    CadastroComercioEntrada entrada,
  ) async {
    _validarEmail(entrada.email);
    final senha = PasswordHasher.criar(entrada.senha);
    final db = await _databaseProvider();
    await db.update('sessoes', {'ativa': 0});
    final agora = DateTime.now().toUtc();
    final comercioId = 'com_${IdGenerator.temporal(agora)}';
    final usuarioId = 'usr_${IdGenerator.temporal()}';
    final codigo = _codigoComercio(comercioId);
    final bookingSlug = await BookingSlug.available(db, entrada.nomeComercio);

    await db.transaction((txn) async {
      await txn.insert('comercios', {
        'id': comercioId,
        'codigo_acesso': codigo,
        'nome': entrada.nomeComercio.trim(),
        'nome_exibicao': entrada.nomeExibicao.trim(),
        'tipo_estabelecimento': entrada.tipoEstabelecimento.name,
        'modulo_loja_ativo':
            entrada.effectiveModuleConfiguration.possui(BusinessModule.loja)
            ? 1
            : 0,
        'modulo_servicos_ativo':
            entrada.effectiveModuleConfiguration.possui(BusinessModule.servicos)
            ? 1
            : 0,
        'modulos_configuracao_json': entrada.effectiveModuleConfiguration
            .toJson(),
        'responsavel': entrada.responsavel.trim(),
        'telefone': entrada.telefone.trim(),
        'email': entrada.email.trim().toLowerCase(),
        'ativo': 1,
        'booking_slug': bookingSlug,
        'booking_enabled': 1,
        'booking_public_url': BookingSlug.publicUrl(bookingSlug),
        'booking_created_at': agora.toIso8601String(),
        'booking_updated_at': agora.toIso8601String(),
        'criado_em': agora.toIso8601String(),
        'atualizado_em': agora.toIso8601String(),
      });
      await _garantirModalidadeInicial(
        txn,
        comercioId,
        agora.toIso8601String(),
      );
      await txn.insert('usuarios', {
        'id': usuarioId,
        'comercio_id': comercioId,
        'nome': entrada.responsavel.trim(),
        'telefone': entrada.telefone.trim(),
        'email_login': entrada.email.trim().toLowerCase(),
        'senha_hash': senha.hash,
        'senha_salt': senha.salt,
        'funcao': FuncaoUsuario.dono.name,
        'ativo': 1,
        'criado_em': agora.toIso8601String(),
        'atualizado_em': agora.toIso8601String(),
      });
      await _salvarPermissoes(txn, usuarioId, ModuloPermissao.values.toSet());
      await _salvarAcoes(
        txn,
        usuarioId,
        comercioId,
        AcaoPermissao.values.toSet(),
      );
      await txn.insert('unidades', {
        'id': 'uni_$comercioId',
        'comercio_id': comercioId,
        'nome': 'Unidade principal',
        'codigo': 'MATRIZ',
        'principal': 1,
        'ativo': 1,
        'criado_em': agora.toIso8601String(),
        'atualizado_em': agora.toIso8601String(),
      });
      await txn.insert('integracoes_configuracao', {
        'comercio_id': comercioId,
        'provedor_backend': 'nenhum',
        'sincronizacao_ativa': 0,
        'atualizado_em': agora.toIso8601String(),
      });
      await txn.insert('assinaturas', {
        'id': 'sub_$comercioId',
        'comercio_id': comercioId,
        'plano': 'unico',
        'status': 'trial',
        'inicio_trial': agora.toIso8601String(),
        'fim_trial': agora.add(const Duration(days: 30)).toIso8601String(),
        'valor_mensal': 24.99,
        'moeda': 'BRL',
        'provedor': 'mock',
        'criado_em': agora.toIso8601String(),
        'atualizado_em': agora.toIso8601String(),
      });
      for (final etapa in const [
        'dados_negocio',
        'logomarca',
        'profissionais',
        'servicos',
        'horarios',
        'agenda',
        'clientes',
        'estoque_salao',
        'loja_salao',
        'estoque_loja',
        'fornecedores',
        'cardapio',
        'ia',
        'pagamentos',
        'assinatura',
      ]) {
        await txn.insert('progresso_configuracao', {
          'comercio_id': comercioId,
          'etapa': etapa,
          'concluida': etapa == 'dados_negocio' ? 1 : 0,
          'atualizado_em': agora.toIso8601String(),
        });
      }
      await _vincularDadosLegados(txn, comercioId);
      await _criarSessao(
        txn,
        usuarioId,
        comercioId,
        persistente: entrada.permanecerConectado,
      );
    });

    return (await carregarUsuario(usuarioId))!;
  }

  Future<UsuarioAcesso> restaurarContaOnline({
    required Map<String, dynamic> account,
    required String senhaValidada,
    required String endpoint,
  }) async {
    final comercioId = account['businessId'] as String;
    final usuarioId = account['userId'] as String;
    final nomeComercio = account['businessName'] as String? ?? 'StudioFlow';
    final nomeUsuario = account['userName'] as String? ?? 'Responsável';
    final login = (account['login'] as String).trim().toLowerCase();
    final telefone = account['phone'] as String? ?? '';
    final funcao = FuncaoUsuarioDados.pelaChave(account['role'] as String?);
    final senha = PasswordHasher.criar(senhaValidada);
    final agora = DateTime.now().toUtc().toIso8601String();
    final db = await _databaseProvider();
    await db.transaction((txn) async {
      await txn.insert('comercios', {
        'id': comercioId,
        'codigo_acesso': _codigoComercio(comercioId),
        'nome': nomeComercio,
        'nome_exibicao': nomeComercio,
        'responsavel': nomeUsuario,
        'telefone': telefone,
        'email': login,
        'ativo': 1,
        'modulo_loja_ativo': (account['moduloLojaAtivo'] == true) ? 1 : 0,
        'modulo_servicos_ativo': (account['moduloServicosAtivo'] == false)
            ? 0
            : 1,
        if (account['segment'] != null)
          'tipo_estabelecimento': account['segment'],
        if (account['moduleConfiguration'] != null)
          'modulos_configuracao_json': account['moduleConfiguration'],
        if (account['bookingSlug'] != null)
          'booking_slug': account['bookingSlug'],
        if (account['bookingEnabled'] != null)
          'booking_enabled': (account['bookingEnabled'] == true) ? 1 : 0,
        if (account['bookingSlug'] != null)
          'booking_public_url': BookingSlug.publicUrl(
            account['bookingSlug'] as String,
          ),
        if (account['bookingSlug'] != null) 'booking_updated_at': agora,
        'criado_em': agora,
        'atualizado_em': agora,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      if (account['bookingSlug'] != null) {
        await txn.update(
          'comercios',
          {
            'booking_slug': account['bookingSlug'],
            'booking_enabled': (account['bookingEnabled'] == true) ? 1 : 0,
            'booking_public_url': BookingSlug.publicUrl(
              account['bookingSlug'] as String,
            ),
            'booking_updated_at': agora,
          },
          where: 'id = ?',
          whereArgs: [comercioId],
        );
      }
      await _garantirModalidadeInicial(txn, comercioId, agora);
      await txn.insert('usuarios', {
        'id': usuarioId,
        'comercio_id': comercioId,
        'nome': nomeUsuario,
        'telefone': telefone,
        'email_login': login,
        'senha_hash': senha.hash,
        'senha_salt': senha.salt,
        'funcao': funcao.name,
        'ativo': 1,
        'criado_em': agora,
        'atualizado_em': agora,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.update(
        'usuarios',
        {
          'nome': nomeUsuario,
          'telefone': telefone,
          'email_login': login,
          'senha_hash': senha.hash,
          'senha_salt': senha.salt,
          'funcao': funcao.name,
          'ativo': 1,
          'atualizado_em': agora,
        },
        where: 'id = ? AND comercio_id = ?',
        whereArgs: [usuarioId, comercioId],
      );
      await _salvarPermissoes(txn, usuarioId, permissoesPadrao(funcao));
      await _salvarAcoes(txn, usuarioId, comercioId, acoesPadrao(funcao));
      await txn.insert('unidades', {
        'id': 'uni_$comercioId',
        'comercio_id': comercioId,
        'nome': 'Unidade principal',
        'codigo': 'MATRIZ',
        'principal': 1,
        'ativo': 1,
        'criado_em': agora,
        'atualizado_em': agora,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.insert('integracoes_configuracao', {
        'comercio_id': comercioId,
        'provedor_backend': 'studioflow_rest',
        'endpoint_publico': endpoint,
        'sincronizacao_ativa': 1,
        'ultimo_cursor': 0,
        'atualizado_em': agora,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.update(
        'integracoes_configuracao',
        {
          'provedor_backend': 'studioflow_rest',
          'endpoint_publico': endpoint,
          'sincronizacao_ativa': 1,
          'ultimo_erro': null,
          'atualizado_em': agora,
        },
        where: 'comercio_id = ?',
        whereArgs: [comercioId],
      );
    });
    return (await carregarUsuario(usuarioId))!;
  }

  Future<List<UsuarioAcesso>> autenticar({
    required String login,
    required String senha,
  }) async {
    final db = await _databaseProvider();
    final registros = await db.rawQuery(
      '''
      SELECT
        u.*,
        c.codigo_acesso,
        c.nome AS comercio_nome,
        c.nome_exibicao,
        c.tipo_estabelecimento,
        c.logo_path,
        c.cor_principal,
        c.cor_secundaria,
        c.cor_destaque,
        c.tema_modo,
        c.tema_automatico,
        c.modulo_loja_ativo,
        c.modulo_servicos_ativo,
        c.modulos_configuracao_json
      FROM usuarios u
      INNER JOIN comercios c ON c.id = u.comercio_id
      WHERE LOWER(u.email_login) = LOWER(?)
        AND u.ativo = 1
        AND c.ativo = 1
      ORDER BY c.nome_exibicao COLLATE NOCASE
      ''',
      [login.trim()],
    );
    final contas = <UsuarioAcesso>[];
    for (final mapa in registros) {
      if (!PasswordHasher.verificar(
        senha,
        mapa['senha_hash'] as String,
        mapa['senha_salt'] as String,
      )) {
        continue;
      }
      final usuarioId = mapa['id'] as String;
      contas.add(
        _montarUsuario(
          mapa,
          await _permissoesDoUsuario(usuarioId),
          await _acoesDoUsuario(usuarioId),
        ),
      );
    }
    if (contas.isEmpty) {
      throw StateError('Login ou senha inválidos.');
    }
    return contas;
  }

  Future<UsuarioAcesso> iniciarSessao({
    required UsuarioAcesso usuario,
    required bool permanecerConectado,
  }) async {
    final db = await _databaseProvider();
    await db.transaction((txn) async {
      await txn.update('sessoes', {'ativa': 0});
      await _criarSessao(
        txn,
        usuario.id,
        usuario.comercioId,
        persistente: permanecerConectado,
      );
    });
    return (await carregarUsuario(usuario.id))!;
  }

  Future<List<UsuarioAcesso>> localizarContasParaRecuperacao(
    String login,
  ) async {
    final db = await _databaseProvider();
    final registros = await db.rawQuery(
      '''
      SELECT
        u.*,
        c.codigo_acesso,
        c.nome AS comercio_nome,
        c.nome_exibicao,
        c.tipo_estabelecimento,
        c.logo_path,
        c.cor_principal,
        c.cor_secundaria,
        c.cor_destaque,
        c.tema_modo,
        c.tema_automatico,
        c.modulo_loja_ativo,
        c.modulo_servicos_ativo,
        c.modulos_configuracao_json
      FROM usuarios u
      INNER JOIN comercios c ON c.id = u.comercio_id
      WHERE LOWER(u.email_login) = LOWER(?)
        AND u.ativo = 1
        AND c.ativo = 1
      ORDER BY c.nome_exibicao COLLATE NOCASE
      ''',
      [login.trim()],
    );
    final contas = <UsuarioAcesso>[];
    for (final mapa in registros) {
      final usuarioId = mapa['id'] as String;
      contas.add(
        _montarUsuario(
          mapa,
          await _permissoesDoUsuario(usuarioId),
          await _acoesDoUsuario(usuarioId),
        ),
      );
    }
    return contas;
  }

  Future<void> redefinirSenhaLocal({
    required String usuarioId,
    required String telefone,
    required String novaSenha,
  }) async {
    if (novaSenha.length < 6) {
      throw const FormatException(
        'A nova senha deve ter ao menos 6 caracteres.',
      );
    }
    final db = await _databaseProvider();
    final registros = await db.rawQuery(
      '''SELECT u.id, u.comercio_id, u.telefone AS usuario_telefone,
         c.telefone AS comercio_telefone
         FROM usuarios u INNER JOIN comercios c ON c.id = u.comercio_id
         WHERE u.id = ? AND u.ativo = 1 AND c.ativo = 1 LIMIT 1''',
      [usuarioId],
    );
    if (registros.isEmpty) throw StateError('Conta não encontrada.');
    final informado = _digitos(telefone);
    final registro = registros.first;
    final corresponde =
        informado.length >= 10 &&
        (informado == _digitos(registro['usuario_telefone'] as String?) ||
            informado == _digitos(registro['comercio_telefone'] as String?));
    final agora = DateTime.now().toUtc().toIso8601String();
    await db.insert('recuperacoes_senha', {
      'id': 'rec_${IdGenerator.temporal()}',
      'usuario_id': usuarioId,
      'comercio_id': registro['comercio_id'],
      'metodo': 'confirmacao_telefone_local',
      'sucesso': corresponde ? 1 : 0,
      'criado_em': agora,
    });
    if (!corresponde) {
      throw StateError('O telefone não confere com o cadastro desta conta.');
    }
    final protegida = PasswordHasher.criar(novaSenha);
    await db.update(
      'usuarios',
      {
        'senha_hash': protegida.hash,
        'senha_salt': protegida.salt,
        'atualizado_em': agora,
      },
      where: 'id = ?',
      whereArgs: [usuarioId],
    );
    await db.update(
      'sessoes',
      {'ativa': 0},
      where: 'usuario_id = ?',
      whereArgs: [usuarioId],
    );
  }

  Future<UsuarioAcesso> login({
    required String codigoComercio,
    required String emailLogin,
    required String senha,
    required bool permanecerConectado,
  }) async {
    final db = await _databaseProvider();
    final resultado = await db.rawQuery(
      '''
      SELECT
        u.*,
        c.codigo_acesso,
        c.nome AS comercio_nome,
        c.nome_exibicao,
        c.tipo_estabelecimento,
        c.logo_path,
        c.cor_principal,
        c.cor_secundaria,
        c.cor_destaque,
        c.tema_modo,
        c.tema_automatico,
        c.modulo_loja_ativo,
        c.modulo_servicos_ativo,
        c.modulos_configuracao_json FROM usuarios u
      INNER JOIN comercios c ON c.id = u.comercio_id
      WHERE UPPER(c.codigo_acesso) = UPPER(?)
        AND LOWER(u.email_login) = LOWER(?)
        AND u.ativo = 1
        AND c.ativo = 1
      LIMIT 1
      ''',
      [codigoComercio.trim(), emailLogin.trim()],
    );

    if (resultado.isEmpty) {
      throw StateError('Comércio, login ou senha inválidos.');
    }

    final mapa = resultado.first;
    if (!PasswordHasher.verificar(
      senha,
      mapa['senha_hash'] as String,
      mapa['senha_salt'] as String,
    )) {
      throw StateError('Comércio, login ou senha inválidos.');
    }

    await db.transaction((txn) async {
      await txn.update(
        'sessoes',
        {'ativa': 0},
        where: 'usuario_id = ?',
        whereArgs: [mapa['id']],
      );
      await _criarSessao(
        txn,
        mapa['id'] as String,
        mapa['comercio_id'] as String,
        persistente: permanecerConectado,
      );
    });

    return _montarUsuario(
      mapa,
      await _permissoesDoUsuario(mapa['id'] as String),
      await _acoesDoUsuario(mapa['id'] as String),
    );
  }

  Future<UsuarioAcesso?> restaurarSessao() async {
    final db = await _databaseProvider();
    await db.update('sessoes', {'ativa': 0}, where: 'persistente = 0');
    final resultado = await db.rawQuery('''
      SELECT usuario_id
      FROM sessoes
      WHERE ativa = 1 AND persistente = 1
      ORDER BY ultimo_acesso DESC
      LIMIT 1
    ''');
    if (resultado.isEmpty) {
      return null;
    }
    final usuario = await carregarUsuario(
      resultado.first['usuario_id'] as String,
    );
    if (usuario == null || !usuario.ativo) {
      await db.update('sessoes', {'ativa': 0});
      return null;
    }
    return usuario;
  }

  Future<void> logout(String usuarioId) async {
    final db = await _databaseProvider();
    await db.update(
      'sessoes',
      {'ativa': 0, 'ultimo_acesso': DateTime.now().toUtc().toIso8601String()},
      where: 'usuario_id = ?',
      whereArgs: [usuarioId],
    );
  }

  Future<UsuarioAcesso?> carregarUsuario(String usuarioId) async {
    final db = await _databaseProvider();
    final resultado = await db.rawQuery(
      '''
      SELECT
        u.*,
        c.codigo_acesso,
        c.nome AS comercio_nome,
        c.nome_exibicao,
        c.tipo_estabelecimento,
        c.logo_path,
        c.cor_principal,
        c.cor_secundaria,
        c.cor_destaque,
        c.tema_modo,
        c.tema_automatico,
        c.modulo_loja_ativo,
        c.modulo_servicos_ativo,
        c.modulos_configuracao_json FROM usuarios u
      INNER JOIN comercios c ON c.id = u.comercio_id
      WHERE u.id = ?
      LIMIT 1
      ''',
      [usuarioId],
    );
    if (resultado.isEmpty) {
      return null;
    }
    return _montarUsuario(
      resultado.first,
      await _permissoesDoUsuario(usuarioId),
      await _acoesDoUsuario(usuarioId),
    );
  }

  Future<List<UsuarioGerenciavel>> listarUsuarios(String comercioId) async {
    final db = await _databaseProvider();
    final registros = await db.query(
      'usuarios',
      where: 'comercio_id = ?',
      whereArgs: [comercioId],
      orderBy: 'ativo DESC, nome COLLATE NOCASE ASC',
    );
    final saida = <UsuarioGerenciavel>[];
    for (final mapa in registros) {
      saida.add(
        UsuarioGerenciavel(
          id: mapa['id'] as String,
          comercioId: mapa['comercio_id'] as String,
          profissionalId: mapa['profissional_id'] as String?,
          nome: mapa['nome'] as String,
          telefone: mapa['telefone'] as String,
          emailLogin: mapa['email_login'] as String,
          funcao: FuncaoUsuarioDados.pelaChave(mapa['funcao'] as String?),
          ativo: (mapa['ativo'] as num) == 1,
          permissoes: await _permissoesDoUsuario(mapa['id'] as String),
          acoes: await _acoesDoUsuario(mapa['id'] as String),
        ),
      );
    }
    return saida;
  }

  Future<void> salvarUsuario({
    required UsuarioAcesso ator,
    String? usuarioId,
    required String nome,
    required String telefone,
    required String emailLogin,
    required String? senha,
    required FuncaoUsuario funcao,
    required bool ativo,
    required Set<ModuloPermissao> permissoes,
    Set<AcaoPermissao>? acoes,
  }) async {
    _validarAdministrador(ator);
    _validarEmail(emailLogin);
    final acoesEfetivas = acoes ?? acoesPadrao(funcao);
    if (funcao == FuncaoUsuario.dono && ator.funcao != FuncaoUsuario.dono) {
      throw StateError('Somente o proprietário pode administrar propriedade.');
    }
    if (usuarioId == ator.id && funcao != ator.funcao) {
      throw StateError('Não é permitido alterar o próprio cargo.');
    }
    if (ator.funcao != FuncaoUsuario.dono &&
        (!ator.permissoes.containsAll(permissoes) ||
            !ator.acoes.containsAll(acoesEfetivas))) {
      throw StateError(
        'Não é permitido conceder permissão superior à própria.',
      );
    }

    final db = await _databaseProvider();
    final duplicado = await db.query(
      'usuarios',
      columns: ['id'],
      where:
          'comercio_id = ? AND LOWER(email_login) = LOWER(?)${usuarioId == null ? '' : ' AND id != ?'}',
      whereArgs: [
        ator.comercioId,
        emailLogin.trim(),
        // ignore: use_null_aware_elements
        if (usuarioId != null) usuarioId,
      ],
      limit: 1,
    );
    if (duplicado.isNotEmpty) {
      throw StateError('Já existe um usuário com este e-mail/login.');
    }

    final agora = DateTime.now().toUtc().toIso8601String();
    final id = usuarioId ?? 'usr_${IdGenerator.temporal()}';
    await db.transaction((txn) async {
      if (usuarioId == null) {
        if (senha == null || senha.isEmpty) {
          throw StateError('Informe uma senha para o novo usuário.');
        }
        final protegida = PasswordHasher.criar(senha);
        final profissionalId = 'pro_${IdGenerator.temporal()}';
        await txn.insert('profissionais', {
          'id': profissionalId,
          'nome': nome.trim(),
          'whatsapp': telefone.trim(),
          'email': emailLogin.trim().toLowerCase(),
          'cargo': funcao.nome,
          'ativo': ativo ? 1 : 0,
          'percentual_comissao': 0,
          'meta_mensal': 0,
          'faturamento_mes': 0,
          'data_cadastro': agora,
          'comercio_id': ator.comercioId,
        });
        await txn.insert('usuarios', {
          'id': id,
          'comercio_id': ator.comercioId,
          'profissional_id': profissionalId,
          'nome': nome.trim(),
          'telefone': telefone.trim(),
          'email_login': emailLogin.trim().toLowerCase(),
          'senha_hash': protegida.hash,
          'senha_salt': protegida.salt,
          'funcao': funcao.name,
          'ativo': ativo ? 1 : 0,
          'criado_em': agora,
          'atualizado_em': agora,
        });
      } else {
        final dados = <String, Object?>{
          'nome': nome.trim(),
          'telefone': telefone.trim(),
          'email_login': emailLogin.trim().toLowerCase(),
          'funcao': funcao.name,
          'ativo': ativo ? 1 : 0,
          'atualizado_em': agora,
        };
        if (senha != null && senha.isNotEmpty) {
          final protegida = PasswordHasher.criar(senha);
          dados['senha_hash'] = protegida.hash;
          dados['senha_salt'] = protegida.salt;
        }
        await txn.update('usuarios', dados, where: 'id = ?', whereArgs: [id]);
        await txn.update(
          'profissionais',
          {
            'nome': nome.trim(),
            'whatsapp': telefone.trim(),
            'email': emailLogin.trim().toLowerCase(),
            'cargo': funcao.nome,
            'ativo': ativo ? 1 : 0,
          },
          where: 'id = (SELECT profissional_id FROM usuarios WHERE id = ?)',
          whereArgs: [id],
        );
      }
      await _salvarPermissoes(
        txn,
        id,
        funcao == FuncaoUsuario.dono
            ? ModuloPermissao.values.toSet()
            : permissoes,
      );
      await _salvarAcoes(
        txn,
        id,
        ator.comercioId,
        funcao == FuncaoUsuario.dono
            ? AcaoPermissao.values.toSet()
            : acoesEfetivas,
      );
    });
  }

  Future<void> excluirUsuario({
    required UsuarioAcesso ator,
    required UsuarioGerenciavel usuario,
  }) async {
    _validarAdministrador(ator);
    if (usuario.id == ator.id || usuario.funcao == FuncaoUsuario.dono) {
      throw StateError('O usuário dono conectado não pode ser excluído.');
    }
    final db = await _databaseProvider();
    await db.transaction((txn) async {
      await txn.delete('usuarios', where: 'id = ?', whereArgs: [usuario.id]);
      if (usuario.profissionalId != null) {
        await txn.update(
          'profissionais',
          {'ativo': 0},
          where: 'id = ?',
          whereArgs: [usuario.profissionalId],
        );
      }
    });
  }

  Future<Set<ModuloPermissao>> _permissoesDoUsuario(String usuarioId) async {
    final db = await _databaseProvider();
    final registros = await db.query(
      'permissoes',
      where: 'usuario_id = ? AND permitido = 1',
      whereArgs: [usuarioId],
    );
    return registros
        .map((item) => item['modulo'] as String)
        .map(
          (chave) => ModuloPermissao.values.where((item) => item.name == chave),
        )
        .expand((item) => item)
        .toSet();
  }

  Future<Set<AcaoPermissao>> _acoesDoUsuario(String usuarioId) async {
    final db = await _databaseProvider();
    final registros = await db.query(
      'permissoes_acoes',
      where: 'usuario_id = ? AND permitido = 1',
      whereArgs: [usuarioId],
    );
    return registros
        .map((item) => item['acao'] as String)
        .map(
          (chave) => AcaoPermissao.values.where((item) => item.name == chave),
        )
        .expand((item) => item)
        .toSet();
  }

  static Future<void> _salvarAcoes(
    DatabaseExecutor db,
    String usuarioId,
    String comercioId,
    Set<AcaoPermissao> acoes,
  ) async {
    await db.delete(
      'permissoes_acoes',
      where: 'usuario_id = ?',
      whereArgs: [usuarioId],
    );
    final agora = DateTime.now().toUtc().toIso8601String();
    for (final acao in AcaoPermissao.values) {
      await db.insert('permissoes_acoes', {
        'usuario_id': usuarioId,
        'comercio_id': comercioId,
        'acao': acao.name,
        'permitido': acoes.contains(acao) ? 1 : 0,
        'atualizado_em': agora,
      });
    }
  }

  static Future<void> _salvarPermissoes(
    DatabaseExecutor db,
    String usuarioId,
    Set<ModuloPermissao> permissoes,
  ) async {
    await db.delete(
      'permissoes',
      where: 'usuario_id = ?',
      whereArgs: [usuarioId],
    );
    for (final modulo in ModuloPermissao.values) {
      await db.insert('permissoes', {
        'usuario_id': usuarioId,
        'modulo': modulo.name,
        'permitido': permissoes.contains(modulo) ? 1 : 0,
      });
    }
  }

  static Future<void> _criarSessao(
    DatabaseExecutor db,
    String usuarioId,
    String comercioId, {
    required bool persistente,
  }) async {
    final agora = DateTime.now().toUtc().toIso8601String();
    await db.insert('sessoes', {
      'id': 'ses_${IdGenerator.temporal()}',
      'usuario_id': usuarioId,
      'comercio_id': comercioId,
      'criada_em': agora,
      'ultimo_acesso': agora,
      'persistente': persistente ? 1 : 0,
      'ativa': 1,
    });
  }

  static Future<void> _vincularDadosLegados(
    DatabaseExecutor db,
    String comercioId,
  ) async {
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
      await db.update(
        tabela,
        {'comercio_id': comercioId},
        where: 'comercio_id = ?',
        whereArgs: [MigrationV2.comercioLegado],
      );
    }
  }

  static UsuarioAcesso _montarUsuario(
    Map<String, Object?> mapa,
    Set<ModuloPermissao> permissoes,
    Set<AcaoPermissao> acoes,
  ) {
    final funcao = FuncaoUsuarioDados.pelaChave(mapa['funcao'] as String?);
    return UsuarioAcesso(
      id: mapa['id'] as String,
      profissionalId: mapa['profissional_id'] as String?,
      comercioId: mapa['comercio_id'] as String,
      codigoComercio: mapa['codigo_acesso'] as String,
      nomeComercio: mapa['comercio_nome'] as String,
      nomeExibicao: mapa['nome_exibicao'] as String,
      nome: mapa['nome'] as String,
      telefone: mapa['telefone'] as String,
      emailLogin: mapa['email_login'] as String,
      funcao: funcao,
      ativo: (mapa['ativo'] as num) == 1,
      permissoes: funcao == FuncaoUsuario.dono
          ? ModuloPermissao.values.toSet()
          : permissoes,
      acoes: funcao == FuncaoUsuario.dono
          ? AcaoPermissao.values.toSet()
          : acoes,
      tipoEstabelecimento: TipoEstabelecimentoDados.pelaChave(
        mapa['tipo_estabelecimento'] as String?,
      ),
      logoPath: mapa['logo_path'] as String? ?? '',
      corPrincipal: mapa['cor_principal'] as String? ?? '#70569A',
      corSecundaria: mapa['cor_secundaria'] as String? ?? '#8B5CF6',
      corDestaque: mapa['cor_destaque'] as String? ?? '#D9C7F2',
      temaModo: mapa['tema_modo'] as String? ?? 'claro',
      temaAutomatico: (mapa['tema_automatico'] as num? ?? 1) == 1,
      capaUrl: mapa['capa_url'] as String? ?? '',
      moduloLojaAtivo: (mapa['modulo_loja_ativo'] as num? ?? 1) == 1,
      moduloServicosAtivo: (mapa['modulo_servicos_ativo'] as num? ?? 1) == 1,
      moduleConfiguration: mapa['modulos_configuracao_json'] == null
          ? null
          : BusinessModuleConfiguration.fromJson(
              mapa['modulos_configuracao_json'] as String,
            ),
    );
  }

  static Future<void> _garantirModalidadeInicial(
    DatabaseExecutor db,
    String comercioId,
    String agora,
  ) => db.insert('modalidades_estabelecimento', {
    'id': 'modalidade_${comercioId}_salao',
    'comercio_id': comercioId,
    'nome': 'Salão de beleza',
    'nome_normalizado': 'salao_de_beleza',
    'descricao': 'Modalidade inicial editável',
    'icone': 'content_cut',
    'cor': '#8E5CE6',
    'ordem': 0,
    'favorita': 1,
    'exibir_home': 1,
    'ativa': 1,
    'personalizada': 0,
    'criado_em': agora,
    'atualizado_em': agora,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
  static String _digitos(String? valor) =>
      (valor ?? '').replaceAll(RegExp(r'\D'), '');
  static String _codigoComercio(String id) {
    final parte = id.replaceAll(RegExp('[^A-Za-z0-9]'), '').toUpperCase();
    final sufixo = parte.length >= 8
        ? parte.substring(parte.length - 8)
        : parte.padLeft(8, '0');
    return 'SF$sufixo';
  }

  static void _validarEmail(String email) {
    final normalizado = email.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalizado)) {
      throw const FormatException('Informe um e-mail válido.');
    }
  }

  static void _validarAdministrador(UsuarioAcesso ator) {
    if (ator.funcao != FuncaoUsuario.dono &&
        !ator.pode(ModuloPermissao.administracaoUsuarios)) {
      throw StateError('Você não possui permissão administrativa.');
    }
  }
}
