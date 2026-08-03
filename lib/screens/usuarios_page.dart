import 'package:flutter/material.dart';

import '../models/domain/acesso.dart';
import '../repositories/acesso_repository.dart';
import '../services/session_controller.dart';

class UsuariosPage extends StatefulWidget {
  const UsuariosPage({super.key});

  @override
  State<UsuariosPage> createState() => _UsuariosPageState();
}

class _UsuariosPageState extends State<UsuariosPage> {
  final _repository = AcessoRepository();
  List<UsuarioGerenciavel> _usuarios = [];
  bool _carregando = true;
  bool _mostrarInativos = true;

  UsuarioAcesso get _ator => SessionController.instance.usuario!;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (!_ator.pode(ModuloPermissao.administracaoUsuarios)) {
      setState(() => _carregando = false);
      return;
    }
    final usuarios = await _repository.listarUsuarios(_ator.comercioId);
    if (!mounted) return;
    setState(() {
      _usuarios = usuarios;
      _carregando = false;
    });
  }

  Future<void> _editar([UsuarioGerenciavel? usuario]) async {
    final resultado = await showModalBottomSheet<_UsuarioEdicao>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UsuarioForm(usuario: usuario),
    );
    if (resultado == null) return;
    try {
      await _repository.salvarUsuario(
        ator: _ator,
        usuarioId: usuario?.id,
        nome: resultado.nome,
        telefone: resultado.telefone,
        emailLogin: resultado.email,
        senha: resultado.senha,
        funcao: resultado.funcao,
        ativo: resultado.ativo,
        permissoes: resultado.permissoes,
        acoes: resultado.acoes,
      );
      await _carregar();
      if (mounted) _mensagem('Usuário salvo com sucesso.');
    } catch (erro) {
      if (mounted) _mensagem(_textoErro(erro));
    }
  }

  Future<void> _excluir(UsuarioGerenciavel usuario) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir usuário?'),
        content: Text(
          'O acesso de ${usuario.nome} será removido. O histórico profissional será preservado como inativo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await _repository.excluirUsuario(ator: _ator, usuario: usuario);
      await _carregar();
    } catch (erro) {
      if (mounted) _mensagem(_textoErro(erro));
    }
  }

  void _mensagem(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  String _textoErro(Object erro) => erro
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('FormatException: ', '');

  @override
  Widget build(BuildContext context) {
    final permitido = _ator.pode(ModuloPermissao.administracaoUsuarios);
    final visiveis = _mostrarInativos
        ? _usuarios
        : _usuarios.where((item) => item.ativo).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Funcionários e acessos')),
      floatingActionButton: permitido
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () => _editar(),
              icon: const Icon(Icons.person_add),
              label: const Text('Novo usuário'),
            )
          : null,
      body: !permitido
          ? const _AcessoNegado()
          : _carregando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                SwitchListTile(
                  value: _mostrarInativos,
                  title: const Text('Mostrar usuários inativos'),
                  onChanged: (valor) =>
                      setState(() => _mostrarInativos = valor),
                ),
                Expanded(
                  child: visiveis.isEmpty
                      ? const Center(child: Text('Nenhum usuário cadastrado.'))
                      : RefreshIndicator(
                          onRefresh: _carregar,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                            itemCount: visiveis.length,
                            itemBuilder: (_, indice) {
                              final usuario = visiveis[indice];
                              return Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    child: Text(
                                      usuario.nome.isEmpty
                                          ? '?'
                                          : usuario.nome[0].toUpperCase(),
                                    ),
                                  ),
                                  title: Text(usuario.nome),
                                  subtitle: Text(
                                    '${usuario.funcao.nome} • ${usuario.emailLogin}\n'
                                    '${usuario.ativo ? 'Ativo' : 'Inativo'}',
                                  ),
                                  isThreeLine: true,
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (acao) {
                                      if (acao == 'editar') _editar(usuario);
                                      if (acao == 'excluir') _excluir(usuario);
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'editar',
                                        child: Text('Editar'),
                                      ),
                                      PopupMenuItem(
                                        value: 'excluir',
                                        child: Text('Excluir'),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

class _AcessoNegado extends StatelessWidget {
  const _AcessoNegado();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 60),
            SizedBox(height: 16),
            Text(
              'Você não possui permissão para administrar usuários.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _UsuarioEdicao {
  final String nome;
  final String telefone;
  final String email;
  final String? senha;
  final FuncaoUsuario funcao;
  final bool ativo;
  final Set<ModuloPermissao> permissoes;
  final Set<AcaoPermissao> acoes;

  const _UsuarioEdicao({
    required this.nome,
    required this.telefone,
    required this.email,
    required this.senha,
    required this.funcao,
    required this.ativo,
    required this.permissoes,
    required this.acoes,
  });
}

class _UsuarioForm extends StatefulWidget {
  final UsuarioGerenciavel? usuario;

  const _UsuarioForm({this.usuario});

  @override
  State<_UsuarioForm> createState() => _UsuarioFormState();
}

class _UsuarioFormState extends State<_UsuarioForm> {
  late final TextEditingController _nome;
  late final TextEditingController _telefone;
  late final TextEditingController _email;
  final _senha = TextEditingController();
  late FuncaoUsuario _funcao;
  late bool _ativo;
  late Set<ModuloPermissao> _permissoes;
  late Set<AcaoPermissao> _acoes;

  @override
  void initState() {
    super.initState();
    final usuario = widget.usuario;
    _nome = TextEditingController(text: usuario?.nome);
    _telefone = TextEditingController(text: usuario?.telefone);
    _email = TextEditingController(text: usuario?.emailLogin);
    _funcao = usuario?.funcao ?? FuncaoUsuario.colaborador;
    _ativo = usuario?.ativo ?? true;
    _permissoes = {...(usuario?.permissoes ?? permissoesPadrao(_funcao))};
    _acoes = {...(usuario?.acoes ?? acoesPadrao(_funcao))};
  }

  @override
  void dispose() {
    _nome.dispose();
    _telefone.dispose();
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  void _salvar() {
    if (_nome.text.trim().isEmpty ||
        _telefone.text.trim().isEmpty ||
        _email.text.trim().isEmpty ||
        (widget.usuario == null && _senha.text.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha os campos obrigatórios.')),
      );
      return;
    }
    Navigator.pop(
      context,
      _UsuarioEdicao(
        nome: _nome.text.trim(),
        telefone: _telefone.text.trim(),
        email: _email.text.trim(),
        senha: _senha.text.isEmpty ? null : _senha.text,
        funcao: _funcao,
        ativo: _ativo,
        permissoes: _permissoes,
        acoes: _acoes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dono = widget.usuario?.funcao == FuncaoUsuario.dono;
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.92,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          children: [
            Text(
              widget.usuario == null ? 'Novo usuário' : 'Editar usuário',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _nome,
              decoration: const InputDecoration(labelText: 'Nome *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _telefone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Telefone *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-mail/login *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _senha,
              obscureText: true,
              decoration: InputDecoration(
                labelText: widget.usuario == null
                    ? 'Senha *'
                    : 'Nova senha (opcional)',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<FuncaoUsuario>(
              initialValue: _funcao,
              decoration: const InputDecoration(labelText: 'Função'),
              items: FuncaoUsuario.values
                  .where((item) => !dono || item == FuncaoUsuario.dono)
                  .where(
                    (item) =>
                        widget.usuario != null || item != FuncaoUsuario.dono,
                  )
                  .map(
                    (item) =>
                        DropdownMenuItem(value: item, child: Text(item.nome)),
                  )
                  .toList(),
              onChanged: dono
                  ? null
                  : (valor) {
                      if (valor == null) return;
                      setState(() {
                        _funcao = valor;
                        _permissoes = permissoesPadrao(valor);
                        _acoes = acoesPadrao(valor);
                      });
                    },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _ativo,
              title: const Text('Usuário ativo'),
              onChanged: dono
                  ? null
                  : (valor) => setState(() => _ativo = valor),
            ),
            const Divider(),
            const Text(
              'Permissões',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            ...ModuloPermissao.values.map(
              (modulo) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value:
                    _funcao == FuncaoUsuario.dono ||
                    _permissoes.contains(modulo),
                title: Text(modulo.nome),
                onChanged: _funcao == FuncaoUsuario.dono
                    ? null
                    : (valor) {
                        setState(() {
                          if (valor == true) {
                            _permissoes.add(modulo);
                          } else {
                            _permissoes.remove(modulo);
                          }
                        });
                      },
              ),
            ),
            const Divider(),
            const Text(
              'Permissões por ação',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Estas regras protegem operações sensíveis mesmo quando o módulo está visível.',
            ),
            ...AcaoPermissao.values.map(
              (acao) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _funcao == FuncaoUsuario.dono || _acoes.contains(acao),
                title: Text(acao.nome),
                subtitle: Text(acao.grupo),
                onChanged: _funcao == FuncaoUsuario.dono
                    ? null
                    : (valor) {
                        setState(() {
                          if (valor == true) {
                            _acoes.add(acao);
                          } else {
                            _acoes.remove(acao);
                          }
                        });
                      },
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _salvar,
              child: const Text('Salvar usuário'),
            ),
          ],
        ),
      ),
    );
  }
}
