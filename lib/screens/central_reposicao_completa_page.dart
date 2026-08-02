import 'package:flutter/material.dart';

import '../models/domain/loja.dart';
import '../repositories/loja_repository.dart';
import '../repositories/reposicao_repository.dart';
import 'suprimentos_page.dart';

class CentralReposicaoCompletaPage extends StatefulWidget {
  const CentralReposicaoCompletaPage({super.key});
  @override
  State<CentralReposicaoCompletaPage> createState() =>
      _CentralReposicaoCompletaPageState();
}

class _CentralReposicaoCompletaPageState
    extends State<CentralReposicaoCompletaPage> {
  final loja = LojaRepository();
  final repo = ReposicaoRepository();
  late Future<List<Map<String, Object?>>> future;
  @override
  void initState() {
    super.initState();
    carregar();
  }

  void carregar() => setState(() => future = loja.listarReposicoes());

  Future<void> adicionar() async {
    final produtos = await loja.listarProdutos();
    if (!mounted) return;
    ProdutoLoja? produto;
    final quantidade = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Adicionar à reposição'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<ProdutoLoja>(
                decoration: const InputDecoration(labelText: 'Produto'),
                items: produtos
                    .map((p) => DropdownMenuItem(value: p, child: Text(p.nome)))
                    .toList(),
                onChanged: (v) => setDialog(() => produto = v),
              ),
              TextField(
                controller: quantidade,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantidade desejada',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: produto == null
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Adicionar'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await repo.adicionarManual(
        produto!.id,
        double.tryParse(quantidade.text.replaceAll(',', '.')) ?? 0,
      );
      carregar();
    }
  }

  Future<void> editar(Map<String, Object?> r) async {
    final qtd = TextEditingController(text: '${r['quantidade_desejada']}');
    final custo = TextEditingController(text: '${r['custo_estimado']}');
    final frete = TextEditingController(text: '${r['frete']}');
    final prazo = TextEditingController(text: '${r['prazo_dias'] ?? ''}');
    final obs = TextEditingController(text: '${r['observacoes'] ?? ''}');
    var status = r['status'] as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(r['produto_nome'] as String),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: qtd,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantidade desejada',
                  ),
                ),
                TextField(
                  controller: custo,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Custo estimado',
                  ),
                ),
                TextField(
                  controller: frete,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Frete'),
                ),
                TextField(
                  controller: prazo,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Prazo em dias'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: ReposicaoRepository.statusPermitidos
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(s.replaceAll('_', ' ')),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setDialog(() => status = v!),
                ),
                TextField(
                  controller: obs,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Observações'),
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
    if (ok == true) {
      await repo.atualizar(
        id: r['id'] as String,
        quantidade: double.tryParse(qtd.text.replaceAll(',', '.')) ?? 0,
        status: status,
        fornecedorId: r['fornecedor_id'] as String?,
        ofertaId: r['oferta_id'] as String?,
        custo: double.tryParse(custo.text.replaceAll(',', '.')) ?? 0,
        frete: double.tryParse(frete.text.replaceAll(',', '.')) ?? 0,
        prazoDias: int.tryParse(prazo.text),
        observacoes: obs.text,
      );
      carregar();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Central de Reposição'),
      actions: [
        IconButton(onPressed: carregar, icon: const Icon(Icons.refresh)),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      heroTag: null,
      onPressed: adicionar,
      icon: const Icon(Icons.add),
      label: const Text('Adicionar'),
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.data!.isEmpty) {
          return const Center(
            child: Text('Nenhum produto aguardando reposição.'),
          );
        }
        return ListView(
          children: snap.data!
              .map(
                (r) => Card(
                  margin: const EdgeInsets.all(8),
                  child: ListTile(
                    title: Text(r['produto_nome'] as String),
                    subtitle: Text(
                      'Atual ${r['quantidade_atual']} • mínimo ${r['estoque_minimo']}\nDesejado ${r['quantidade_desejada']} • ${(r['status'] as String).replaceAll('_', ' ')}',
                    ),
                    isThreeLine: true,
                    onTap: () => editar(r),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'comparar') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ComparadorReposicaoPage(
                                termoInicial: r['produto_nome'] as String,
                                produtoId: r['produto_id'] as String,
                              ),
                            ),
                          );
                        }
                        if (v == 'ordem') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CriarOrdemPage(
                                produtoId: r['produto_id'] as String,
                                quantidade: (r['quantidade_desejada'] as num)
                                    .toDouble(),
                              ),
                            ),
                          );
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'comparar',
                          child: Text('Comparar ofertas'),
                        ),
                        PopupMenuItem(
                          value: 'ordem',
                          child: Text('Criar ordem'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    ),
  );
}
