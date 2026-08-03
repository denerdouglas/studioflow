import 'package:flutter/material.dart';

import '../repositories/consignacao_repository.dart';

class JoiasConsignadasPage extends StatefulWidget {
  const JoiasConsignadasPage({super.key});

  @override
  State<JoiasConsignadasPage> createState() => _JoiasConsignadasPageState();
}

class _JoiasConsignadasPageState extends State<JoiasConsignadasPage> {
  final repo = ConsignacaoRepository();
  late Future<List<Map<String, Object?>>> future = repo.listar();

  void reload() => setState(() => future = repo.listar());

  Future<void> create() async {
    final suppliers = await repo.fornecedores();
    if (!mounted) return;
    if (suppliers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cadastre um fornecedor primeiro.')),
      );
      return;
    }
    var supplier = suppliers.first['id'] as String;
    final lot = TextEditingController();
    final code = TextEditingController();
    final name = TextEditingController();
    final description = TextEditingController();
    final price = TextEditingController();
    final transfer = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: const Text('Nova maleta/lote'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: supplier,
                  items: suppliers
                      .map(
                        (item) => DropdownMenuItem(
                          value: item['id'] as String,
                          child: Text(item['nome'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setD(() => supplier = value!),
                  decoration: const InputDecoration(labelText: 'Fornecedor'),
                ),
                TextField(
                  controller: lot,
                  decoration: const InputDecoration(
                    labelText: 'Nome da maleta',
                  ),
                ),
                TextField(
                  controller: code,
                  decoration: const InputDecoration(
                    labelText: 'Código único da peça',
                  ),
                ),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nome da peça'),
                ),
                TextField(
                  controller: description,
                  decoration: const InputDecoration(labelText: 'Descrição'),
                ),
                TextField(
                  controller: price,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Preço'),
                ),
                TextField(
                  controller: transfer,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Repasse ao fornecedor',
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
              child: const Text('Criar lote'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await repo.receberMaleta(
      fornecedorId: supplier,
      nomeLote: lot.text,
      pecas: [
        {
          'codigo': code.text,
          'nome': name.text,
          'descricao': description.text,
          'preco': double.parse(price.text.replaceAll(',', '.')),
          'repasse': double.tryParse(transfer.text.replaceAll(',', '.')) ?? 0,
        },
      ],
    );
    reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Joias consignadas e maletas')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: create,
      icon: const Icon(Icons.add),
      label: const Text('Nova maleta'),
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(child: Text('Nenhuma maleta cadastrada.'));
        }
        return ListView(
          children: snapshot.data!
              .map(
                (lot) => ListTile(
                  title: Text(
                    '${lot['nome_lote'] ?? lot['lote_colecao'] ?? 'Maleta'} • ${lot['fornecedor_nome']}',
                  ),
                  subtitle: Text(
                    '${lot['status']} • recebidas ${lot['quantidade_recebida'] ?? 0} • vendidas ${lot['quantidade_vendida'] ?? 0} • disponíveis ${lot['quantidade_disponivel'] ?? 0}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => JoiasLotePage(lote: lot)),
                  ).then((_) => reload()),
                ),
              )
              .toList(),
        );
      },
    ),
  );
}

class JoiasLotePage extends StatefulWidget {
  final Map<String, Object?> lote;
  const JoiasLotePage({super.key, required this.lote});

  @override
  State<JoiasLotePage> createState() => _JoiasLotePageState();
}

class _JoiasLotePageState extends State<JoiasLotePage> {
  final repo = ConsignacaoRepository();
  late Future<List<Map<String, Object?>>> future = repo.pecas(
    widget.lote['id'] as String,
  );

  void reload() =>
      setState(() => future = repo.pecas(widget.lote['id'] as String));

  Future<void> status(Map<String, Object?> piece, String value) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Alterar para $value?'),
        content: Text('${piece['codigo_exclusivo']} • ${piece['nome']}'),
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
    );
    if (confirmed == true) {
      if (value == 'devolvida') {
        await repo.devolverPeca(piece['id'] as String);
      } else {
        await repo.alterarStatusPeca(piece['id'] as String, value);
      }
      reload();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.lote['nome_lote'] as String? ?? 'Maleta'),
      actions: [
        IconButton(
          tooltip: 'Arquivar lote conferido',
          icon: const Icon(Icons.archive_outlined),
          onPressed: () async {
            await repo.arquivarMaleta(widget.lote['id'] as String);
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ],
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          children: snapshot.data!
              .map(
                (piece) => ListTile(
                  title: Text(
                    '${piece['codigo_exclusivo']} • ${piece['nome']}',
                  ),
                  subtitle: Text(
                    '${piece['status']} • R\$ ${(piece['preco'] as num).toStringAsFixed(2)}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) => status(piece, value),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'reservada',
                        child: Text('Reservar'),
                      ),
                      PopupMenuItem(
                        value: 'em_comanda',
                        child: Text('Colocar em comanda'),
                      ),
                      PopupMenuItem(
                        value: 'devolvida',
                        child: Text('Devolver'),
                      ),
                      PopupMenuItem(
                        value: 'perdida',
                        child: Text('Marcar perdida'),
                      ),
                      PopupMenuItem(
                        value: 'avariada',
                        child: Text('Marcar avariada'),
                      ),
                      PopupMenuItem(
                        value: 'transferida',
                        child: Text('Transferir'),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      },
    ),
  );
}
