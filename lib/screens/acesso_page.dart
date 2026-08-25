import 'package:flutter/material.dart';

import '../core/utils/id_generator.dart';
import '../models/domain/acesso.dart';
import '../repositories/acesso_repository.dart';
import '../repositories/equipe_repository.dart';
import '../services/preferencias_service.dart';
import '../services/acesso_online_service.dart';
import '../services/backend_sync_service.dart';
import '../services/session_controller.dart';

class AcessoPage extends StatefulWidget {
  final bool carregarCadastroLegado;

  const AcessoPage({super.key, this.carregarCadastroLegado = true});

  @override
  State<AcessoPage> createState() => _AcessoPageState();
}

class _AcessoPageState extends State<AcessoPage>
    with SingleTickerProviderStateMixin {
  late final TabController _abas;
  final _repository = AcessoRepository();
  final _online = AcessoOnlineService();
  final _login = TextEditingController();
  final _senhaLogin = TextEditingController();
  final _nomeComercio = TextEditingController();
  final _nomeExibicao = TextEditingController();
  final _responsavel = TextEditingController();
  final _telefone = TextEditingController();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  final _confirmacao = TextEditingController();
  final _codigoUnidade = TextEditingController();
  bool _cadastroProprietario = true;
  bool _permanecer = true;
  bool _somenteLoja = false;
  TipoEstabelecimento _tipoEstabelecimento = TipoEstabelecimento.salao;
  bool _ocultarSenha = true;
  bool _processando = false;

  @override
  void initState() {
    super.initState();
    _abas = TabController(length: 2, vsync: this);
    if (widget.carregarCadastroLegado) {
      _carregarLegado();
    }
  }

  Future<void> _carregarLegado() async {
    if (!await PreferenciasService.cadastroConcluido()) return;
    final cadastro = await PreferenciasService.carregarCadastro();
    if (!mounted) return;
    _nomeComercio.text = cadastro['nomeNegocio'] ?? '';
    _nomeExibicao.text = cadastro['nomeNegocio'] ?? '';
    _responsavel.text = cadastro['nomeResponsavel'] ?? '';
  }

  @override
  void dispose() {
    _abas.dispose();
    for (final controller in [
      _login,
      _senhaLogin,
      _nomeComercio,
      _nomeExibicao,
      _responsavel,
      _telefone,
      _email,
      _senha,
      _confirmacao,
      _codigoUnidade,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _mensagem(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _entrar() async {
    if (_login.text.trim().isEmpty || _senhaLogin.text.isEmpty) {
      _mensagem('Informe seu e-mail/login e senha.');
      return;
    }
    setState(() => _processando = true);
    try {
      UsuarioAcesso? selecionada;
      Object? erroLocal;
      try {
        final contas = await _repository.autenticar(
          login: _login.text,
          senha: _senhaLogin.text,
        );
        selecionada = await _selecionarContaLocal(contas);
      } on Object catch (erro) {
        erroLocal = erro;
      }

      var online = false;
      String? avisoOffline;
      if (_online.configurado) {
        try {
          var resultado = await _online.entrar(
            login: _login.text,
            senha: _senhaLogin.text,
            comercioId: selecionada?.comercioId,
          );
          if (resultado.exigeSelecao) {
            final comercioId = await _selecionarContaOnline(resultado.contas);
            if (comercioId == null) return;
            resultado = await _online.entrar(
              login: _login.text,
              senha: _senhaLogin.text,
              comercioId: comercioId,
            );
          }
          selecionada = resultado.usuario ?? selecionada;
          online = resultado.usuario != null;
          if (online && selecionada != null) {
            try {
              await BackendSyncService().sincronizar(selecionada.comercioId);
            } catch (erro) {
              avisoOffline =
                  'Login online confirmado, mas a sincronização inicial ficou pendente: $erro';
            }
          }
        } on Object catch (_) {
          if (selecionada == null) rethrow;
          avisoOffline =
              'Servidor indisponível. Entrada liberada no modo offline porque a senha foi validada neste aparelho.';
        }
      } else if (selecionada == null && erroLocal != null) {
        throw erroLocal;
      }

      if (selecionada == null) {
        throw StateError('Não foi possível validar esta conta.');
      }
      final usuario = await _repository.iniciarSessao(
        usuario: selecionada,
        permanecerConectado: _permanecer,
      );
      if (avisoOffline != null && mounted) _mensagem(avisoOffline);
      SessionController.instance.entrar(usuario);
      if (online) {
        // A sincronização automática continuará após a entrada.
      }
    } catch (erro) {
      if (mounted) _mensagem(_textoErro(erro));
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<UsuarioAcesso?> _selecionarContaLocal(
    List<UsuarioAcesso> contas,
  ) async {
    if (contas.length == 1) return contas.first;
    if (!mounted) return null;
    return showDialog<UsuarioAcesso>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SimpleDialog(
        title: const Text('Escolha o estabelecimento'),
        children: contas
            .map(
              (conta) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, conta),
                child: ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text(conta.nomeExibicao),
                  subtitle: Text(conta.tipoEstabelecimento.nome),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Future<String?> _selecionarContaOnline(
    List<Map<String, dynamic>> contas,
  ) async {
    if (contas.length == 1) return contas.single['businessId'] as String;
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SimpleDialog(
        title: const Text('Escolha o estabelecimento online'),
        children: contas
            .map(
              (conta) => SimpleDialogOption(
                onPressed: () =>
                    Navigator.pop(context, conta['businessId'] as String),
                child: ListTile(
                  leading: const Icon(Icons.cloud_done_outlined),
                  title: Text(conta['businessName'] as String? ?? 'StudioFlow'),
                  subtitle: Text(conta['role'] as String? ?? ''),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Future<void> _recuperarSenha() async {
    final login = TextEditingController(text: _login.text.trim());
    final telefone = TextEditingController();
    final novaSenha = TextEditingController();
    final confirmacao = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recuperar senha neste aparelho'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'A recuperação local confirma o login e o telefone já cadastrado. Ela não envia SMS ou e-mail.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: login,
                decoration: const InputDecoration(labelText: 'E-mail ou login'),
              ),
              TextField(
                controller: telefone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Telefone cadastrado',
                ),
              ),
              TextField(
                controller: novaSenha,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Nova senha'),
              ),
              TextField(
                controller: confirmacao,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirmar nova senha',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (confirmar != true) {
      login.dispose();
      telefone.dispose();
      novaSenha.dispose();
      confirmacao.dispose();
      return;
    }
    try {
      if (novaSenha.text != confirmacao.text) {
        throw const FormatException('A confirmação da senha não confere.');
      }
      final contas = await _repository.localizarContasParaRecuperacao(
        login.text,
      );
      if (contas.isEmpty) {
        throw StateError('Nenhuma conta ativa foi encontrada.');
      }
      UsuarioAcesso? conta = contas.first;
      if (contas.length > 1 && mounted) {
        conta = await showDialog<UsuarioAcesso>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Escolha o estabelecimento'),
            children: contas
                .map(
                  (item) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, item),
                    child: Text(item.nomeExibicao),
                  ),
                )
                .toList(),
          ),
        );
      }
      if (conta == null) return;
      await _repository.redefinirSenhaLocal(
        usuarioId: conta.id,
        telefone: telefone.text,
        novaSenha: novaSenha.text,
      );
      if (mounted) _mensagem('Senha atualizada. Entre com a nova senha.');
    } catch (erro) {
      if (mounted) _mensagem(_textoErro(erro));
    } finally {
      login.dispose();
      telefone.dispose();
      novaSenha.dispose();
      confirmacao.dispose();
    }
  }

  Future<void> _cadastrar() async {
    if (!_cadastroProprietario) {
      await _solicitarAcesso();
      return;
    }
    if ([
      _nomeComercio,
      _nomeExibicao,
      _responsavel,
      _telefone,
      _email,
      _senha,
      _confirmacao,
    ].any((item) => item.text.trim().isEmpty)) {
      _mensagem('Preencha todos os campos obrigatórios.');
      return;
    }
    if (_senha.text != _confirmacao.text) {
      _mensagem('A confirmação de senha não confere.');
      return;
    }
    setState(() => _processando = true);
    try {
      final entrada = CadastroComercioEntrada(
        nomeComercio: _nomeComercio.text,
        nomeExibicao: _nomeExibicao.text,
        responsavel: _responsavel.text,
        telefone: _telefone.text,
        email: _email.text,
        senha: _senha.text,
        permanecerConectado: _permanecer,
        tipoEstabelecimento: _tipoEstabelecimento,
        moduloLojaAtivo: true,
        moduloServicosAtivo: !_somenteLoja,
      );

      if (!_online.configurado) {
        throw StateError(
          'O StudioFlow Cloud não está configurado nesta versão. '
          'Novos cadastros exigem conexão com a nuvem.',
        );
      }

      final comercioId = 'com_${IdGenerator.temporal(DateTime.now().toUtc())}';
      final usuarioId = 'usr_${IdGenerator.temporal()}';

      final usuario = await _online.cadastrar(
        entrada: entrada,
        comercioId: comercioId,
        usuarioId: usuarioId,
      );

      try {
        await BackendSyncService().sincronizar(usuario.comercioId);
      } catch (e) {
        // Ignora erro de sincronização inicial na UI, será feito em background
      }

      await PreferenciasService.salvarCadastro(
        nomeResponsavel: usuario.nome,
        nomeNegocio: usuario.nomeComercio,
        tipoNegocio: 'Beleza',
        tema: 'elegante',
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Estabelecimento criado'),
          content: Text(
            '${usuario.nomeExibicao} foi cadastrado no StudioFlow Cloud. Nos próximos acessos, use somente seu e-mail/login e senha.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      SessionController.instance.entrar(usuario);
    } catch (erro) {
      if (mounted) _mensagem(_textoErro(erro));
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _solicitarAcesso() async {
    if ([
      _responsavel,
      _telefone,
      _email,
      _senha,
      _confirmacao,
      _codigoUnidade,
    ].any((item) => item.text.trim().isEmpty)) {
      _mensagem('Preencha todos os campos obrigatórios.');
      return;
    }
    if (_senha.text != _confirmacao.text) {
      _mensagem('A confirmação de senha não confere.');
      return;
    }
    setState(() => _processando = true);
    try {
      final repository = EquipeRepository();
      final business = await repository.localizarUnidade(_codigoUnidade.text);
      if (business == null) throw StateError('Unidade não encontrada.');
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmar unidade'),
          content: Text(business['nome']!),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enviar solicitação'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await repository.solicitarAcesso(
        businessId: business['id']!,
        nome: _responsavel.text,
        telefone: _telefone.text,
        login: _email.text,
        senha: _senha.text,
      );
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Aguardando aprovação'),
            content: const Text(
              'O código não concede acesso. Aguarde a aprovação da proprietária.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendi'),
              ),
            ],
          ),
        );
      }
    } catch (error) {
      if (mounted) _mensagem(_textoErro(error));
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  String _textoErro(Object erro) {
    return erro
        .toString()
        .replaceFirst('Bad state: ', '')
        .replaceFirst('FormatException: ', '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F6FC),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: Color(0xFF70569A),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'StudioFlow',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D2140),
                    ),
                  ),
                  const Text('Acesso seguro ao seu comércio'),
                ],
              ),
            ),
            TabBar(
              controller: _abas,
              labelColor: const Color(0xFF70569A),
              tabs: const [
                Tab(text: 'Entrar'),
                Tab(text: 'Cadastrar comércio'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _abas,
                children: [_formularioLogin(), _formularioCadastro()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formularioLogin() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _campo(
          _login,
          'E-mail ou login',
          Icons.alternate_email,
          teclado: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        _campoSenha(_senhaLogin, 'Senha'),
        _permanecerConectado(),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _processando ? null : _entrar,
          icon: const Icon(Icons.login),
          label: Text(_processando ? 'Entrando...' : 'Entrar'),
          style: _botaoStyle(),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _processando ? null : _recuperarSenha,
          child: const Text('Esqueci minha senha'),
        ),
        const Text(
          'A recuperação disponível nesta versão é local. Recuperação remota dependerá de um backend seguro.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF766A85), fontSize: 12),
        ),
      ],
    );
  }

  Widget _formularioCadastro() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Sou proprietário')),
            ButtonSegment(value: false, label: Text('Sou colaborador')),
          ],
          selected: {_cadastroProprietario},
          onSelectionChanged: (value) =>
              setState(() => _cadastroProprietario = value.single),
        ),
        const SizedBox(height: 16),
        if (!_cadastroProprietario) ...[
          _campo(_codigoUnidade, 'Código público da unidade *', Icons.key),
          const SizedBox(height: 12),
        ],
if (_cadastroProprietario) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Como voc pretende usar o StudioFlow?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Servios + Loja')),
              ButtonSegment(value: true, label: Text('Somente Loja')),
            ],
            selected: {_somenteLoja},
            onSelectionChanged: (value) =>
                setState(() => _somenteLoja = value.single),
          ),
          const SizedBox(height: 12),
        ],
        _campo(_nomeComercio, _somenteLoja ? 'Nome do negcio *' : 'Nome do estabelecimento *', Icons.store),
        const SizedBox(height: 12),
        _campo(_nomeExibicao, 'Nome exibido no aplicativo *', Icons.badge),
        const SizedBox(height: 12),
        DropdownButtonFormField<TipoEstabelecimento>(
          initialValue: _tipoEstabelecimento,
          decoration: const InputDecoration(
            labelText: 'Tipo do estabelecimento',
            prefixIcon: Icon(Icons.category_outlined),
          ),
          items: TipoEstabelecimento.values
              .map(
                (tipo) => DropdownMenuItem(value: tipo, child: Text(tipo.nome)),
              )
              .toList(),
          onChanged: (tipo) {
            if (tipo != null) {
              setState(() => _tipoEstabelecimento = tipo);
            }
          },
        ),
        const SizedBox(height: 12),
        _campo(_responsavel, 'Nome do responsável *', Icons.person),
        const SizedBox(height: 12),
        _campo(
          _telefone,
          'Telefone/WhatsApp *',
          Icons.phone,
          teclado: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        _campo(
          _email,
          'E-mail de acesso *',
          Icons.email,
          teclado: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        _campoSenha(_senha, 'Senha *'),
        const SizedBox(height: 12),
        _campoSenha(_confirmacao, 'Confirmar senha *'),
        _permanecerConectado(),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _processando ? null : _cadastrar,
          icon: const Icon(Icons.add_business),
          label: Text(_processando ? 'Criando...' : 'Criar comércio e entrar'),
          style: _botaoStyle(),
        ),
      ],
    );
  }

  Widget _campo(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? teclado,
  }) {
    return TextField(
      controller: controller,
      keyboardType: teclado,
      textCapitalization: teclado == null
          ? TextCapitalization.words
          : TextCapitalization.none,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    );
  }

  Widget _campoSenha(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      obscureText: _ocultarSenha,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          onPressed: () => setState(() => _ocultarSenha = !_ocultarSenha),
          icon: Icon(
            _ocultarSenha ? Icons.visibility_outlined : Icons.visibility_off,
          ),
        ),
      ),
    );
  }

  Widget _permanecerConectado() {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: _permanecer,
      title: const Text('Permanecer conectado'),
      onChanged: (valor) => setState(() => _permanecer = valor),
    );
  }

  ButtonStyle _botaoStyle() {
    return FilledButton.styleFrom(
      backgroundColor: const Color(0xFF70569A),
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(56),
    );
  }
}
