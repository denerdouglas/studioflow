import 'package:flutter/material.dart';

import '../models/domain/acesso.dart';
import '../repositories/acesso_repository.dart';
import '../repositories/equipe_repository.dart';
import '../services/session_controller.dart';

class EquipePage extends StatefulWidget {
  const EquipePage({super.key});

  @override
  State<EquipePage> createState() => _EquipePageState();
}

class _EquipePageState extends State<EquipePage>
    with SingleTickerProviderStateMixin {
  final _repository = EquipeRepository();
  final _access = AcessoRepository();
  late final TabController _tabs;
  List<UsuarioGerenciavel> _users = const [];
  List<SolicitacaoEquipe> _requests = const [];
  List<OpcaoEquipe> _areas = const [];
  List<OpcaoEquipe> _services = const [];
  CapacidadeEquipe _capacity = const CapacidadeEquipe(0, 3);
  bool _loading = true;

  UsuarioAcesso get _actor => SessionController.instance.usuario!;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait([
      _access.listarUsuarios(_actor.comercioId),
      _repository.listarSolicitacoes(_actor.comercioId),
      _repository.capacidade(_actor.comercioId),
      _repository.listarModalidades(_actor.comercioId),
      _repository.listarServicos(_actor.comercioId),
    ]);
    if (!mounted) return;
    setState(() {
      _users = values[0] as List<UsuarioGerenciavel>;
      _requests = values[1] as List<SolicitacaoEquipe>;
      _capacity = values[2] as CapacidadeEquipe;
      _areas = values[3] as List<OpcaoEquipe>;
      _services = values[4] as List<OpcaoEquipe>;
      _loading = false;
    });
  }

  Future<void> _review(SolicitacaoEquipe request) async {
    final result = await _editor(title: request.nome);
    if (result == null) return;
    try {
      await _repository.aprovar(
        ator: _actor,
        solicitacaoId: request.id,
        funcao: result.role,
        permissoes: result.modules,
        acoes: result.actions,
        modalidadeIds: result.areas,
        servicos: result.services,
      );
      await _load();
    } catch (error) {
      _message(error);
    }
  }

  Future<void> _view(UsuarioGerenciavel user) async {
    final detail = await _repository.detalhe(user);
    if (!mounted) return;
    String names(Iterable<String> ids, List<OpcaoEquipe> options) => ids
        .map((id) => options.where((o) => o.id == id).firstOrNull?.nome ?? id)
        .join(', ');
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(user.nome),
        content: SingleChildScrollView(
          child: Text(
            'Cargo: ${user.funcao.nome}\n'
            'Unidade: ${detail.unidade}\n'
            'Status: ${user.ativo ? 'Ativo' : 'Inativo'}\n'
            'Áreas: ${names(detail.modalidadeIds, _areas)}\n'
            'Serviços: ${names(detail.servicos.keys, _services)}\n'
            'Comissões: ${detail.comissoesEfetivas.entries.map((e) => '${_services.where((s) => s.id == e.key).firstOrNull?.nome ?? e.key}: ${e.value}%').join(', ')}\n'
            'Permissões principais: ${user.permissoes.map((e) => e.nome).join(', ')}',
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(UsuarioGerenciavel user) async {
    final detail = await _repository.detalhe(user);
    if (!mounted) return;
    final result = await _editor(title: user.nome, detail: detail);
    if (result == null) return;
    try {
      await _repository.editar(
        ator: _actor,
        usuario: user,
        funcao: result.role,
        permissoes: result.modules,
        acoes: result.actions,
        modalidadeIds: result.areas,
        servicos: result.services,
      );
    } on StateError catch (error) {
      if (!error.message.toString().contains('agendamentos futuros') ||
          !mounted) {
        _message(error);
        return;
      }
      final confirmed = await _confirm(error.message.toString());
      if (!confirmed) return;
      await _repository.editar(
        ator: _actor,
        usuario: user,
        funcao: result.role,
        permissoes: result.modules,
        acoes: result.actions,
        modalidadeIds: result.areas,
        servicos: result.services,
        confirmarRemocaoComAgenda: true,
      );
    }
    await _load();
  }

  Future<void> _status(UsuarioGerenciavel user) async {
    if (user.ativo) {
      final future = await _repository.agendamentosFuturos(user);
      final text = future == 0
          ? 'Desativar o acesso desta unidade?'
          : 'Existem $future agendamentos futuros. Desativar mesmo assim?';
      if (!await _confirm(text)) return;
    }
    try {
      await _repository.alterarAtivo(
        ator: _actor,
        usuario: user,
        ativo: !user.ativo,
      );
      await _load();
    } catch (error) {
      _message(error);
    }
  }

  Future<_EquipeEdicao?> _editor({
    required String title,
    EquipeDetalhe? detail,
  }) async {
    var role = detail?.usuario.funcao ?? FuncaoUsuario.colaborador;
    var modules = {...(detail?.usuario.permissoes ?? permissoesPadrao(role))};
    var actions = {...(detail?.usuario.acoes ?? acoesPadrao(role))};
    var areas = {...?detail?.modalidadeIds};
    var services = <String, double?>{...?detail?.servicos};
    final commissions = <String, TextEditingController>{
      for (final item in _services)
        item.id: TextEditingController(
          text: services[item.id]?.toString() ?? '',
        ),
    };
    final result = await showDialog<_EquipeEdicao>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, change) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<FuncaoUsuario>(
                    initialValue: role,
                    decoration: const InputDecoration(labelText: 'Cargo'),
                    items: const [
                      DropdownMenuItem(
                        value: FuncaoUsuario.colaborador,
                        child: Text('Colaborador'),
                      ),
                      DropdownMenuItem(
                        value: FuncaoUsuario.gerente,
                        child: Text('Gerente'),
                      ),
                    ],
                    onChanged: (value) => change(() {
                      role = value!;
                      modules = permissoesPadrao(role);
                      actions = acoesPadrao(role);
                    }),
                  ),
                  const SizedBox(height: 12),
                  const Text('Áreas'),
                  ..._areas.map(
                    (item) => CheckboxListTile(
                      dense: true,
                      value: areas.contains(item.id),
                      title: Text(item.nome),
                      onChanged: (value) => change(
                        () => value == true
                            ? areas.add(item.id)
                            : areas.remove(item.id),
                      ),
                    ),
                  ),
                  const Text('Serviços e comissão override'),
                  ..._services.map(
                    (item) => CheckboxListTile(
                      dense: true,
                      value: services.containsKey(item.id),
                      title: Text(item.nome),
                      subtitle: services.containsKey(item.id)
                          ? TextField(
                              controller: commissions[item.id],
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: item.comissao == null
                                    ? 'Override opcional (%)'
                                    : 'Override opcional; serviço ${item.comissao}%',
                              ),
                            )
                          : null,
                      onChanged: (value) => change(
                        () => value == true
                            ? services[item.id] = null
                            : services.remove(item.id),
                      ),
                    ),
                  ),
                  Text('Preset ${role.nome} + personalização'),
                  ...ModuloPermissao.values.map(
                    (item) => CheckboxListTile(
                      dense: true,
                      value: modules.contains(item),
                      title: Text(item.nome),
                      onChanged: (value) => change(
                        () => value == true
                            ? modules.add(item)
                            : modules.remove(item),
                      ),
                    ),
                  ),
                  ExpansionTile(
                    title: const Text('Permissões operacionais'),
                    children: AcaoPermissao.values
                        .map(
                          (item) => CheckboxListTile(
                            dense: true,
                            value: actions.contains(item),
                            title: Text(item.nome),
                            onChanged: (value) => change(
                              () => value == true
                                  ? actions.add(item)
                                  : actions.remove(item),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final selected = <String, double?>{};
                for (final id in services.keys) {
                  final text = commissions[id]!.text.trim().replaceAll(
                    ',',
                    '.',
                  );
                  final value = text.isEmpty ? null : double.tryParse(text);
                  if (value != null && (value < 0 || value > 100)) return;
                  selected[id] = value;
                }
                Navigator.pop(
                  context,
                  _EquipeEdicao(role, areas, selected, modules, actions),
                );
              },
              child: Text(detail == null ? 'Aprovar' : 'Salvar'),
            ),
          ],
        ),
      ),
    );
    for (final controller in commissions.values) {
      controller.dispose();
    }
    return result;
  }

  Future<bool> _confirm(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmar'),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _showCode() async {
    final code = await _repository.codigoPublico(_actor.comercioId);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Código público da unidade'),
        content: SelectableText(code, style: const TextStyle(fontSize: 24)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  void _message(Object error) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
  );

  @override
  Widget build(BuildContext context) {
    if (_actor.funcao != FuncaoUsuario.dono) {
      return const Scaffold(body: Center(child: Text('Acesso não permitido.')));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Equipe'),
        actions: [
          IconButton(
            tooltip: 'Código público',
            onPressed: _showCode,
            icon: const Icon(Icons.key_outlined),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Ativos'),
            Tab(text: 'Solicitações'),
            Tab(text: 'Inativos'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '${_capacity.utilizados} de ${_capacity.capacidade} vagas utilizadas.',
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _people(_users.where((u) => u.ativo)),
                      _requestList(),
                      _people(_users.where((u) => !u.ativo)),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _people(Iterable<UsuarioGerenciavel> values) {
    final items = values.toList();
    if (items.isEmpty) return const Center(child: Text('Nenhuma pessoa.'));
    return ListView(
      children: items
          .map(
            (user) => Card(
              child: ListTile(
                title: Text(user.nome),
                subtitle: Text(
                  '${user.funcao.nome} • ${user.ativo ? 'Ativo' : 'Inativo'}',
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'view') _view(user);
                    if (action == 'edit') _edit(user);
                    if (action == 'status') _status(user);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'view', child: Text('Ver')),
                    const PopupMenuItem(value: 'edit', child: Text('Editar')),
                    PopupMenuItem(
                      value: 'status',
                      child: Text(user.ativo ? 'Desativar' : 'Reativar'),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _requestList() => _requests.isEmpty
      ? const Center(child: Text('Nenhuma solicitação.'))
      : ListView(
          children: _requests
              .map(
                (request) => Card(
                  child: ListTile(
                    title: Text(request.nome),
                    subtitle: Text(
                      request.status == 'pending_billing'
                          ? 'Aguardando ajuste do plano'
                          : 'Aguardando aprovação',
                    ),
                    onTap: () => _review(request),
                  ),
                ),
              )
              .toList(),
        );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }
}

class _EquipeEdicao {
  final FuncaoUsuario role;
  final Set<String> areas;
  final Map<String, double?> services;
  final Set<ModuloPermissao> modules;
  final Set<AcaoPermissao> actions;

  const _EquipeEdicao(
    this.role,
    this.areas,
    this.services,
    this.modules,
    this.actions,
  );
}
