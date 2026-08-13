import 'package:flutter/material.dart';

import '../models/domain/acesso.dart';
import '../repositories/equipe_repository.dart';
import '../services/session_controller.dart';

class MinhasUnidadesPage extends StatefulWidget {
  const MinhasUnidadesPage({super.key});

  @override
  State<MinhasUnidadesPage> createState() => _MinhasUnidadesPageState();
}

class _MinhasUnidadesPageState extends State<MinhasUnidadesPage> {
  final _repository = EquipeRepository();
  List<UsuarioAcesso>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final current = SessionController.instance.usuario!;
    final items = await _repository.minhasUnidades(current);
    if (mounted) setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Minhas unidades')),
    body: _items == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: _items!
                .map(
                  (item) => Card(
                    child: ListTile(
                      title: Text(item.nomeExibicao),
                      subtitle: Text(item.funcao.nome),
                      trailing:
                          item.comercioId ==
                              SessionController.instance.usuario?.comercioId
                          ? const Chip(label: Text('Atual'))
                          : FilledButton(
                              onPressed: () async {
                                await SessionController.instance.trocarBusiness(
                                  item,
                                );
                                if (context.mounted) Navigator.pop(context);
                              },
                              child: const Text('Trocar'),
                            ),
                    ),
                  ),
                )
                .toList(),
          ),
  );
}
