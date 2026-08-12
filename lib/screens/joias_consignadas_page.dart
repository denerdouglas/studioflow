import 'package:flutter/material.dart';

import '../repositories/consignacao_repository.dart';
import '../repositories/cliente_repository.dart';
import 'nova_remessa_consignacao_page.dart';

class JoiasConsignadasPage extends StatefulWidget {
  const JoiasConsignadasPage({super.key});

  @override
  State<JoiasConsignadasPage> createState() => _JoiasConsignadasPageState();
}

class _JoiasConsignadasPageState extends State<JoiasConsignadasPage> {
  final repo = ConsignacaoRepository();
  late Future<List<Map<String, Object?>>> future = repo.listar();
  bool historico = false;

  void reload() => setState(() => future = repo.listar());

  Future<void> create() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const NovaRemessaConsignacaoPage()),
    );
    if (created == true) reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Loja • Consignados')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: create,
      icon: const Icon(Icons.add),
      label: const Text('Nova remessa'),
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final lots = snapshot.data!
            .where(
              (lot) => historico
                  ? lot['status'] != 'aberta'
                  : lot['status'] == 'aberta',
            )
            .toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Remessas ativas')),
                  ButtonSegment(value: true, label: Text('Histórico')),
                ],
                selected: {historico},
                onSelectionChanged: (value) =>
                    setState(() => historico = value.single),
              ),
            ),
            Expanded(
              child: lots.isEmpty
                  ? Center(
                      child: Text(
                        historico
                            ? 'Nenhuma remessa no histórico.'
                            : 'Nenhuma remessa ativa.',
                      ),
                    )
                  : ListView.builder(
                      itemCount: lots.length,
                      itemBuilder: (context, index) {
                        final lot = lots[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: ListTile(
                            title: Text(
                              '${lot['nome_lote'] ?? lot['lote_colecao'] ?? 'Remessa'} • ${lot['fornecedor_nome'] ?? 'Fornecedor'}',
                            ),
                            subtitle: Text(
                              '${lot['status'] ?? 'aberta'} • recebidas ${lot['quantidade_recebida'] ?? 0} • vendidas ${lot['quantidade_vendida'] ?? 0} • disponíveis ${lot['quantidade_disponivel'] ?? 0}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => JoiasLotePage(lote: lot),
                              ),
                            ).then((_) => reload()),
                          ),
                        );
                      },
                    ),
            ),
          ],
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
  final pesquisa = TextEditingController();
  String? filtro;
  late Future<List<Map<String, Object?>>> future;
  late Future<Map<String, Object?>> detail;

  @override
  void initState() {
    super.initState();
    future = repo.pecas(widget.lote['id'] as String);
    detail = repo.detalhe(widget.lote['id'] as String);
  }

  void reload() => setState(() {
    future = repo.pecas(
      widget.lote['id'] as String,
      status: filtro,
      pesquisa: pesquisa.text,
    );
    detail = repo.detalhe(widget.lote['id'] as String);
  });

  @override
  void dispose() {
    pesquisa.dispose();
    super.dispose();
  }

  Future<void> devolver(Map<String, Object?> piece) async {
    await repo.devolverPeca(piece['id'] as String);
    reload();
  }

  Future<void> vender(Map<String, Object?> piece) async {
    final clients = await ClienteRepository().listar();
    if (!mounted) return;
    final price = TextEditingController(text: '${piece['preco'] ?? 0}');
    var payment = 'pix';
    var clientId = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Vender peça exata'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${piece['codigo_exclusivo']} • ${piece['nome']}'),
              TextField(
                controller: price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Valor da venda'),
              ),
              DropdownButtonFormField<String>(
                initialValue: payment,
                decoration: const InputDecoration(labelText: 'Pagamento'),
                items: const [
                  DropdownMenuItem(value: 'pix', child: Text('Pix')),
                  DropdownMenuItem(value: 'dinheiro', child: Text('Dinheiro')),
                  DropdownMenuItem(value: 'cartao', child: Text('Cartão')),
                ],
                onChanged: (value) => setDialog(() => payment = value!),
              ),
              DropdownButtonFormField<String>(
                initialValue: clientId,
                decoration: const InputDecoration(
                  labelText: 'Cliente (opcional)',
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Venda sem cliente'),
                  ),
                  ...clients.map(
                    (client) => DropdownMenuItem(
                      value: client.id,
                      child: Text(client.nome),
                    ),
                  ),
                ],
                onChanged: (value) => setDialog(() => clientId = value ?? ''),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar venda'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await repo.venderPeca(
      piece['id'] as String,
      valor: double.tryParse(price.text.replaceAll(',', '.')),
      formaPagamento: payment,
      clienteId: clientId.isEmpty ? null : clientId,
    );
    reload();
  }

  Future<void> fechar() async {
    final available = await repo.pecas(
      widget.lote['id'] as String,
      status: 'disponivel',
      limit: 1000,
    );
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fechar/trocar remessa'),
        content: Text(
          'As ${available.length} peças disponíveis serão devolvidas. Peças vendidas e eventos serão preservados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Devolver e fechar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await repo.fecharRemessa(
      widget.lote['id'] as String,
      pecasDevolvidas: available.map((piece) => piece['id'] as String),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${widget.lote['nome_lote'] ?? 'Remessa'}'),
      actions: [
        if (widget.lote['status'] == 'aberta')
          IconButton(
            tooltip: 'Fechar/trocar remessa',
            onPressed: fechar,
            icon: const Icon(Icons.inventory_2_outlined),
          ),
      ],
    ),
    body: Column(
      children: [
        FutureBuilder<Map<String, Object?>>(
          future: detail,
          builder: (context, snapshot) {
            final data = snapshot.data;
            if (data == null) return const LinearProgressIndicator();
            return Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text('Recebidas: ${data['quantidade_real'] ?? 0}'),
                    Text('Vendidas: ${data['vendidas_real'] ?? 0}'),
                    Text('Disponíveis: ${data['disponiveis_real'] ?? 0}'),
                    Text('Devolvidas: ${data['devolvidas_real'] ?? 0}'),
                    Text(
                      'Mercadoria: R\$ ${_money(data['valor_recebido_real'])}',
                    ),
                    Text('Vendido: R\$ ${_money(data['valor_vendido_real'])}'),
                    Text('Em posse: R\$ ${_money(data['valor_posse_real'])}'),
                  ],
                ),
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: pesquisa,
            onChanged: (_) => reload(),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Buscar código, categoria ou descrição',
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'todas', label: Text('Todas')),
              ButtonSegment(value: 'disponivel', label: Text('Disponíveis')),
              ButtonSegment(value: 'vendida', label: Text('Vendidas')),
              ButtonSegment(value: 'devolvida', label: Text('Devolvidas')),
            ],
            selected: {filtro ?? 'todas'},
            onSelectionChanged: (value) {
              filtro = value.single == 'todas' ? null : value.single;
              reload();
            },
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, Object?>>>(
            future: future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView.builder(
                itemCount: snapshot.data!.length,
                itemBuilder: (context, index) {
                  final piece = snapshot.data![index];
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: ListTile(
                      title: Text(
                        '${piece['codigo_exclusivo']} • ${piece['nome']}',
                      ),
                      subtitle: Text(
                        '${piece['status']} • R\$ ${_money(piece['preco'])}',
                      ),
                      trailing: piece['status'] == 'disponivel'
                          ? PopupMenuButton<String>(
                              onSelected: (value) => value == 'vendida'
                                  ? vender(piece)
                                  : devolver(piece),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'vendida',
                                  child: Text('Vender'),
                                ),
                                PopupMenuItem(
                                  value: 'devolvida',
                                  child: Text('Devolver'),
                                ),
                              ],
                            )
                          : null,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );

  static String _money(Object? value) =>
      (value is num ? value.toDouble() : 0).toStringAsFixed(2);
}
