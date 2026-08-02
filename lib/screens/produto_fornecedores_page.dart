import 'package:flutter/material.dart';

import '../models/domain/loja.dart';
import '../repositories/loja_repository.dart';
import '../repositories/produto_fornecedor_repository.dart';

class ProdutoFornecedoresPage extends StatefulWidget {
  const ProdutoFornecedoresPage({super.key});
  @override
  State<ProdutoFornecedoresPage> createState() =>
      _ProdutoFornecedoresPageState();
}

class _ProdutoFornecedoresPageState extends State<ProdutoFornecedoresPage> {
  final repo = ProdutoFornecedorRepository();
  late Future<List<Map<String, Object?>>> future;
  @override
  void initState() {
    super.initState();
    carregar();
  }

  void carregar() => setState(() => future = repo.listar());

  Future<void> novo() async {
    final loja = LojaRepository();
    final produtos = await loja.listarProdutos();
    final fornecedores = await loja.listarFornecedores(ativos: true);
    if (!mounted) return;
    ProdutoLoja? produto;
    FornecedorLoja? fornecedor;
    final codigo = TextEditingController();
    final preco = TextEditingController();
    final embalagem = TextEditingController(text: '1');
    final prazo = TextEditingController(text: '0');
    final link = TextEditingController();
    final obs = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Vincular fornecedor'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<ProdutoLoja>(
                  decoration: const InputDecoration(labelText: 'Produto'),
                  items: produtos
                      .map(
                        (p) => DropdownMenuItem(value: p, child: Text(p.nome)),
                      )
                      .toList(),
                  onChanged: (v) => setDialog(() => produto = v),
                ),
                DropdownButtonFormField<FornecedorLoja>(
                  decoration: const InputDecoration(labelText: 'Fornecedor'),
                  items: fornecedores
                      .map(
                        (f) => DropdownMenuItem(value: f, child: Text(f.nome)),
                      )
                      .toList(),
                  onChanged: (v) => setDialog(() => fornecedor = v),
                ),
                TextField(
                  controller: codigo,
                  decoration: const InputDecoration(
                    labelText: 'Código no fornecedor',
                  ),
                ),
                TextField(
                  controller: preco,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Preço mais recente',
                  ),
                ),
                TextField(
                  controller: embalagem,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantidade por embalagem',
                  ),
                ),
                TextField(
                  controller: prazo,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Prazo em dias'),
                ),
                TextField(
                  controller: link,
                  decoration: const InputDecoration(labelText: 'Link'),
                ),
                TextField(
                  controller: obs,
                  decoration: const InputDecoration(labelText: 'Observação'),
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
              onPressed: produto == null || fornecedor == null
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await repo.salvar(
        produtoId: produto!.id,
        fornecedorId: fornecedor!.id,
        codigoFornecedor: codigo.text,
        preco: double.tryParse(preco.text.replaceAll(',', '.')) ?? 0,
        quantidadeEmbalagem:
            double.tryParse(embalagem.text.replaceAll(',', '.')) ?? 1,
        prazoDias: int.tryParse(prazo.text) ?? 0,
        link: link.text,
        observacao: obs.text,
      );
      carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Produtos e fornecedores')),
    floatingActionButton: FloatingActionButton.extended(
      heroTag: null,
      onPressed: novo,
      icon: const Icon(Icons.add_link),
      label: const Text('Vincular'),
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.data!.isEmpty) {
          return const Center(
            child: Text('Nenhum fornecedor vinculado a produto.'),
          );
        }
        return ListView(
          children: snap.data!
              .map(
                (v) => ListTile(
                  title: Text('${v['produto_nome']} • ${v['fornecedor_nome']}'),
                  subtitle: Text(
                    'R\$ ${(v['preco_recente'] as num).toStringAsFixed(2)} • embalagem ${v['quantidade_embalagem']} • ${v['prazo_dias']} dias',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await repo.excluir(
                        v['produto_id'] as String,
                        v['fornecedor_id'] as String,
                      );
                      carregar();
                    },
                  ),
                ),
              )
              .toList(),
        );
      },
    ),
  );
}
