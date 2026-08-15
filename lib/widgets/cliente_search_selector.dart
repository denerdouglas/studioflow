import 'package:flutter/material.dart';

import '../repositories/cliente_repository.dart';

class ClienteSearchSelector extends StatefulWidget {
  final bool permitirSemCliente;

  const ClienteSearchSelector({super.key, this.permitirSemCliente = true});

  @override
  State<ClienteSearchSelector> createState() => _ClienteSearchSelectorState();
}

class _ClienteSearchSelectorState extends State<ClienteSearchSelector> {
  final _repository = ClienteRepository();
  final _searchController = TextEditingController();
  List<ClienteRegistro> _todosClientes = [];
  List<ClienteRegistro> _clientesFiltrados = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregarClientes();
  }

  Future<void> _carregarClientes() async {
    try {
      final clientes = await _repository.listar();
      if (!mounted) return;
      setState(() {
        _todosClientes = clientes;
        _clientesFiltrados = clientes;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao carregar clientes.')),
      );
    }
  }

  void _filtrar(String query) {
    if (query.isEmpty) {
      setState(() => _clientesFiltrados = _todosClientes);
      return;
    }

    final lowerQuery = query.toLowerCase();
    setState(() {
      _clientesFiltrados = _todosClientes.where((c) {
        final nomeMatch = c.nome.toLowerCase().contains(lowerQuery);
        final wppMatch = c.whatsapp
            .replaceAll(RegExp(r'\D'), '')
            .contains(
              RegExp(r'\D').hasMatch(query)
                  ? query
                  : query.replaceAll(RegExp(r'\D'), ''),
            );
        return nomeMatch || wppMatch;
      }).toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onChanged: _filtrar,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Pesquisar cliente',
                hintText: 'Nome ou WhatsApp',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _filtrar('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          if (_carregando)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: ListView(
                children: [
                  if (widget.permitirSemCliente &&
                      _searchController.text.isEmpty)
                    ListTile(
                      leading: const Icon(Icons.person_off_outlined),
                      title: const Text('Venda sem cliente'),
                      onTap: () => Navigator.pop(context, 'sem_cliente'),
                    ),
                  if (_clientesFiltrados.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(
                        child: Text(
                          'Nenhum cliente encontrado.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ..._clientesFiltrados.map(
                    (c) => ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(c.nome),
                      subtitle: Text(c.whatsapp),
                      onTap: () => Navigator.pop(context, c),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
