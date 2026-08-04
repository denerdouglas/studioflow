import 'package:flutter/material.dart';

import '../repositories/modalidades_repository.dart';

class ModalidadesPage extends StatefulWidget {
  const ModalidadesPage({super.key});

  @override
  State<ModalidadesPage> createState() => _ModalidadesPageState();
}

class _ModalidadesPageState extends State<ModalidadesPage> {
  final _repository = ModalidadesRepository();
  List<ModalidadeRegistro> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _items = await _repository.listar();
    } catch (error) {
      if (mounted) _message('$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([ModalidadeRegistro? current]) async {
    final name = TextEditingController(text: current?.nome ?? '');
    final description = TextEditingController(text: current?.descricao ?? '');
    final cover = TextEditingController(text: current?.imagemCapa ?? '');
    var icon = current?.icone ?? 'category';
    var color = current?.cor ?? '#8E5CE6';
    var favorite = current?.favorita ?? false;
    var showHome = current?.exibirHome ?? true;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(
            current == null ? 'Adicionar modalidade' : 'Editar modalidade',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nome *'),
                ),
                TextField(
                  controller: description,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Descrição'),
                ),
                TextField(
                  controller: cover,
                  decoration: const InputDecoration(
                    labelText: 'Imagem/capa (opcional)',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: icon,
                  decoration: const InputDecoration(labelText: 'Ícone'),
                  items: const [
                    DropdownMenuItem(
                      value: 'category',
                      child: Text('Categoria'),
                    ),
                    DropdownMenuItem(
                      value: 'content_cut',
                      child: Text('Salão'),
                    ),
                    DropdownMenuItem(value: 'spa', child: Text('Spa/Estética')),
                    DropdownMenuItem(value: 'face', child: Text('Beleza')),
                    DropdownMenuItem(
                      value: 'restaurant',
                      child: Text('Alimentos'),
                    ),
                  ],
                  onChanged: (value) => setLocal(() => icon = value!),
                ),
                DropdownButtonFormField<String>(
                  initialValue: color,
                  decoration: const InputDecoration(labelText: 'Cor'),
                  items: const [
                    DropdownMenuItem(value: '#8E5CE6', child: Text('Roxo')),
                    DropdownMenuItem(value: '#E8578B', child: Text('Rosa')),
                    DropdownMenuItem(value: '#2979FF', child: Text('Azul')),
                    DropdownMenuItem(value: '#00A884', child: Text('Verde')),
                    DropdownMenuItem(value: '#F59E0B', child: Text('Dourado')),
                  ],
                  onChanged: (value) => setLocal(() => color = value!),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: favorite,
                  title: const Text('Modalidade favorita'),
                  onChanged: (value) => setLocal(() => favorite = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: showHome,
                  title: const Text('Exibir atalho na Home'),
                  onChanged: (value) => setLocal(() => showHome = value),
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
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (save != true) return;
    try {
      await _repository.salvar(
        ModalidadeRegistro(
          id: current?.id ?? '',
          nome: name.text,
          descricao: description.text,
          imagemCapa: cover.text,
          icone: icon,
          cor: color,
          ordem: current?.ordem ?? _items.length,
          favorita: favorite,
          exibirHome: showHome,
          ativa: current?.ativa ?? true,
          personalizada: current?.personalizada ?? true,
        ),
      );
      await _load();
    } catch (error) {
      if (mounted) _message('$error');
    }
  }

  Future<void> _links(ModalidadeRegistro item) async {
    final options = await _repository.opcoesVinculos(item.id);
    final selected = <String, Set<String>>{
      for (final entry in options.entries)
        entry.key: entry.value
            .where((row) => row['selecionado'] == 1)
            .map((row) => row['id'] as String)
            .toSet(),
    };
    if (!mounted) return;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Vínculos · ${item.nome}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                children: options.entries.map((entry) {
                  final title = switch (entry.key) {
                    'servicos' => 'Serviços',
                    'profissionais' => 'Colaboradores',
                    _ => 'Estoque',
                  };
                  return ExpansionTile(
                    title: Text(title),
                    subtitle: Text(
                      '${selected[entry.key]!.length} selecionado(s)',
                    ),
                    children: entry.value
                        .map(
                          (row) => CheckboxListTile(
                            value: selected[entry.key]!.contains(row['id']),
                            title: Text(row['nome'] as String),
                            onChanged: (value) => setLocal(() {
                              if (value == true) {
                                selected[entry.key]!.add(row['id'] as String);
                              } else {
                                selected[entry.key]!.remove(row['id']);
                              }
                            }),
                          ),
                        )
                        .toList(),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Salvar vínculos'),
            ),
          ],
        ),
      ),
    );
    if (save != true) return;
    await _repository.salvarVinculos(
      item.id,
      servicos: selected['servicos']!,
      profissionais: selected['profissionais']!,
      estoque: selected['estoque']!,
      funcoes: selected['funcoes']!,
    );
    if (mounted) _message('Vínculos atualizados sem duplicar cadastros.');
  }

  Future<void> _delete(ModalidadeRegistro item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir modalidade?'),
        content: const Text(
          'A exclusão física só ocorre quando não existe vínculo ou histórico. Caso exista, use Inativar.',
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
    if (confirmed != true) return;
    try {
      await _repository.excluir(item.id);
      await _load();
    } catch (error) {
      if (mounted) _message('$error');
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  IconData _icon(String value) => switch (value) {
    'content_cut' => Icons.content_cut,
    'spa' => Icons.spa_outlined,
    'face' => Icons.face_retouching_natural,
    'restaurant' => Icons.restaurant_outlined,
    _ => Icons.category_outlined,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Modalidades do estabelecimento')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _edit,
      icon: const Icon(Icons.add),
      label: const Text('Adicionar modalidade'),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: _items.length,
            onReorderItem: (oldIndex, newIndex) async {
              if (newIndex > oldIndex) newIndex--;
              final changed = [..._items];
              final item = changed.removeAt(oldIndex);
              changed.insert(newIndex, item);
              setState(() => _items = changed);
              await _repository.reordenar(changed.map((e) => e.id).toList());
            },
            itemBuilder: (context, index) {
              final item = _items[index];
              return Card(
                key: ValueKey(item.id),
                child: ListTile(
                  leading: CircleAvatar(child: Icon(_icon(item.icone))),
                  title: Text(item.nome),
                  subtitle: Text(
                    '${item.ativa ? 'Ativa' : 'Inativa'}${item.favorita ? ' · favorita' : ''}${item.exibirHome ? ' · Home' : ''}\n${item.descricao}',
                  ),
                  isThreeLine: item.descricao.isNotEmpty,
                  onTap: () => _edit(item),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) async {
                      if (action == 'edit') await _edit(item);
                      if (action == 'links') await _links(item);
                      if (action == 'status') {
                        await _repository.alterarStatus(item.id, !item.ativa);
                        await _load();
                      }
                      if (action == 'delete') await _delete(item);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Editar')),
                      const PopupMenuItem(
                        value: 'links',
                        child: Text('Serviços, equipe e estoque'),
                      ),
                      PopupMenuItem(
                        value: 'status',
                        child: Text(item.ativa ? 'Inativar' : 'Reativar'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Excluir'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
  );
}
