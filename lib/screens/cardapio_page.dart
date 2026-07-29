import 'package:flutter/material.dart';

import '../repositories/cardapio_repository.dart';

class MenuPage extends StatefulWidget {
  const MenuPage({super.key});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  final _repository = MenuRepository();
  List<MenuItem> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _repository.list();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _edit([MenuItem? item]) async {
    final name = TextEditingController(text: item?.name ?? '');
    final description = TextEditingController(text: item?.description ?? '');
    final category = TextEditingController(text: item?.category ?? 'Bebidas');
    final price = TextEditingController(
      text: item?.price.toStringAsFixed(2) ?? '0,00',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item == null ? 'Novo item do cardápio' : 'Editar item'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nome *'),
              ),
              TextField(
                controller: description,
                decoration: const InputDecoration(labelText: 'Descrição'),
              ),
              TextField(
                controller: category,
                decoration: const InputDecoration(labelText: 'Categoria *'),
              ),
              TextField(
                controller: price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Preço (R\$); use 0 para cortesia',
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
            onPressed: () async {
              try {
                await _repository.save(
                  id: item?.id,
                  name: name.text,
                  description: description.text,
                  category: category.text,
                  price: double.tryParse(price.text.replaceAll(',', '.')) ?? -1,
                  active: item?.active ?? true,
                );
                if (context.mounted) Navigator.pop(context, true);
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        error.toString().replaceFirst('Bad state: ', ''),
                      ),
                    ),
                  );
                }
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    name.dispose();
    description.dispose();
    category.dispose();
    price.dispose();
    if (saved == true) await _load();
  }

  Future<void> _remove(MenuItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir item?'),
        content: Text('Deseja excluir “${item.name}” e seus complementos?'),
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
    if (confirmed == true) {
      await _repository.delete(item.id);
      await _load();
    }
  }

  Future<void> _addComplement(MenuItem item) async {
    final name = TextEditingController();
    final price = TextEditingController(text: '0,00');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Complemento para ${item.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            TextField(
              controller: price,
              decoration: const InputDecoration(labelText: 'Valor adicional'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              await _repository.addComplement(
                item.id,
                name: name.text,
                additionalPrice:
                    double.tryParse(price.text.replaceAll(',', '.')) ?? -1,
              );
              if (context.mounted) Navigator.pop(context, true);
            },
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    name.dispose();
    price.dispose();
    if (saved == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Complemento adicionado.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cardápio do Salão')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _edit,
      icon: const Icon(Icons.add),
      label: const Text('Novo item'),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _items.isEmpty
        ? const Center(
            child: Text(
              'Nenhum item. Cadastre bebidas, cortesias ou complementos.',
            ),
          )
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(
                        item.price == 0 ? Icons.redeem : Icons.local_cafe,
                      ),
                    ),
                    title: Text(item.name),
                    subtitle: Text(
                      '${item.category} • ${item.price == 0 ? 'Cortesia' : 'R\$ ${item.price.toStringAsFixed(2)}'}',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        switch (value) {
                          case 'edit':
                            await _edit(item);
                          case 'complement':
                            await _addComplement(item);
                          case 'status':
                            await _repository.setActive(item.id, !item.active);
                            await _load();
                          case 'delete':
                            await _remove(item);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Editar'),
                        ),
                        const PopupMenuItem(
                          value: 'complement',
                          child: Text('Adicionar complemento'),
                        ),
                        PopupMenuItem(
                          value: 'status',
                          child: Text(item.active ? 'Desativar' : 'Ativar'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Excluir'),
                        ),
                      ],
                    ),
                    enabled: item.active,
                    onTap: () => _edit(item),
                  ),
                );
              },
            ),
          ),
  );
}
