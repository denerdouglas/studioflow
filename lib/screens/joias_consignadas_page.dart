import 'package:flutter/material.dart';

import '../core/helpers/app_formatters.dart';
import '../repositories/consignacao_repository.dart';
import '../repositories/cliente_repository.dart';
import '../repositories/consignacao_acerto_repository.dart';
import 'nova_remessa_consignacao_page.dart';
import 'consignacao_conferencia_page.dart';
import 'consignacao_acerto_page.dart';

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
    appBar: AppBar(title: Text('Loja • Consignados')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: create,
      icon: Icon(Icons.add),
      label: Text('Nova remessa'),
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator());
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
                            trailing: Icon(Icons.chevron_right),
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
  final selecionadas = <String>{};
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
          title: Text('Vender peça exata'),
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
              child: Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Confirmar venda'),
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

  Future<void> finalizarComanda() async {
    final clients = await ClienteRepository().listar();
    if (!mounted) return;
    var clientId = clients.firstOrNull?.id ?? '';
    var payment = 'pix';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('Finalizar comanda • ${selecionadas.length} peça(s)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: clientId,
                decoration: const InputDecoration(labelText: 'Cliente'),
                items: clients
                    .map(
                      (client) => DropdownMenuItem(
                        value: client.id,
                        child: Text(client.nome),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialog(() => clientId = value ?? ''),
              ),
              DropdownButtonFormField<String>(
                initialValue: payment,
                decoration: const InputDecoration(labelText: 'Pagamento'),
                items: const [
                  DropdownMenuItem(value: 'pix', child: Text('Pix')),
                  DropdownMenuItem(value: 'dinheiro', child: Text('Dinheiro')),
                  DropdownMenuItem(value: 'cartao', child: Text('Cartão')),
                ],
                onChanged: (value) => setDialog(() => payment = value ?? 'pix'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Adicionar mais itens'),
            ),
            FilledButton(
              onPressed: clientId.isEmpty
                  ? null
                  : () => Navigator.pop(context, true),
              child: Text('Finalizar comanda'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    await repo.venderPecas(
      selecionadas,
      clienteId: clientId,
      formaPagamento: payment,
    );
    setState(selecionadas.clear);
    reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Venda finalizada com sucesso')),
      );
    }
  }

  Future<void> acaoVenda(Map<String, Object?> piece, String action) async {
    final sale = await repo.vendaDaPeca(piece['id'] as String);
    if (!mounted) return;
    if (action == 'view') {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Venda da peça'),
          content: Text(
            '${piece['codigo_exclusivo']} • ${piece['nome']}\n'
            'Cliente: ${sale['cliente_nome'] ?? 'Não informado'}\n'
            'Valor: ${_money(sale['valor_total'])}\n'
            'Pagamento: ${sale['forma_pagamento'] ?? 'Não informado'}\n'
            'Data: ${sale['data_venda']}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Fechar'),
            ),
          ],
        ),
      );
      return;
    }
    if (action == 'refund') {
      final reason = TextEditingController();
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Devolver/Estornar'),
          content: TextField(
            controller: reason,
            decoration: const InputDecoration(labelText: 'Motivo obrigatório'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Estornar'),
            ),
          ],
        ),
      );
      if (accepted == true) {
        await repo.estornarVendaDaPeca(piece['id'] as String, reason.text);
        reload();
      }
      return;
    }
    final clients = await ClienteRepository().listar();
    if (!mounted) return;
    var clientId = '${sale['cliente_id'] ?? ''}';
    final payment = TextEditingController(
      text: '${sale['forma_pagamento'] ?? 'pix'}',
    );
    final notes = TextEditingController(text: '${sale['observacoes'] ?? ''}');
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('Editar venda'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: clientId,
                decoration: const InputDecoration(labelText: 'Cliente'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Sem cliente')),
                  ...clients.map(
                    (client) => DropdownMenuItem(
                      value: client.id,
                      child: Text(client.nome),
                    ),
                  ),
                ],
                onChanged: (value) => setDialog(() => clientId = value ?? ''),
              ),
              TextField(
                controller: payment,
                decoration: const InputDecoration(
                  labelText: 'Forma de pagamento',
                ),
              ),
              TextField(
                controller: notes,
                decoration: const InputDecoration(labelText: 'Observação'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      await repo.editarVendaDaPeca(
        piece['id'] as String,
        clienteId: clientId.isEmpty ? null : clientId,
        formaPagamento: payment.text,
        observacoes: notes.text,
      );
      reload();
    }
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
        title: Text('Fechar/trocar remessa'),
        content: Text(
          'As ${available.length} peças disponíveis serão devolvidas. Peças vendidas e eventos serão preservados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Devolver e fechar'),
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

  Future<void> acerto() async {
    final quantidade = TextEditingController();
    final valor = TextEditingController();
    final repasse = TextEditingController();
    final taxas = TextEditingController(text: '0');
    final perdas = TextEditingController(text: '0');
    final ajustes = TextEditingController(text: '0');
    var confirmarDivergencia = false;
    var marcarPago = false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Acerto da remessa'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: quantidade,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantidade informada pela fornecedora',
                  ),
                ),
                TextField(
                  controller: valor,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Valor informado pela fornecedora',
                  ),
                ),
                TextField(
                  controller: repasse,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Repasse'),
                ),
                TextField(
                  controller: taxas,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Taxas'),
                ),
                TextField(
                  controller: perdas,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Perdas'),
                ),
                TextField(
                  controller: ajustes,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Ajuste (+/-)'),
                ),
                CheckboxListTile(
                  value: confirmarDivergencia,
                  onChanged: (value) =>
                      setLocal(() => confirmarDivergencia = value ?? false),
                  title: Text('Confirmar eventual divergência'),
                ),
                CheckboxListTile(
                  value: marcarPago,
                  onChanged: (value) =>
                      setLocal(() => marcarPago = value ?? false),
                  title: Text('Pagamento realmente efetuado'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Conferir acerto'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    double number(String text) =>
        double.tryParse(text.replaceAll(',', '.')) ?? 0;
    try {
      final repository = ConsignacaoAcertoRepository();
      final saved = await repository.salvar(
        widget.lote['id'] as String,
        ConsignacaoAcertoInput(
          quantidadeFornecedor: int.tryParse(quantidade.text),
          valorFornecedor: valor.text.trim().isEmpty
              ? null
              : number(valor.text),
          repasse: number(repasse.text),
          taxas: number(taxas.text),
          perdasFinanceiras: number(perdas.text),
          ajustes: number(ajustes.text),
          confirmarDivergencia: confirmarDivergencia,
        ),
      );
      final id = saved['id'] as String;
      await repository.marcarConferido(id);
      if (marcarPago) await repository.pagar(id);
      reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${widget.lote['nome_lote'] ?? 'Remessa'}'),
      actions: [
        IconButton(
          tooltip: 'Acerto financeiro',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  ConsignacaoAcertoPage(remessaId: widget.lote['id'] as String),
            ),
          ).then((_) => reload()),
          icon: Icon(Icons.request_quote_outlined),
        ),
        IconButton(
          tooltip: 'Conferir por Bip',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ConsignacaoConferenciaPage(
                remessaId: widget.lote['id'] as String,
                finalidade: 'inventario',
              ),
            ),
          ).then((_) => reload()),
          icon: Icon(Icons.qr_code_scanner),
        ),
        if (widget.lote['status'] == 'aberta')
          IconButton(
            tooltip: 'Devolução por Bip',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ConsignacaoConferenciaPage(
                  remessaId: widget.lote['id'] as String,
                  finalidade: 'devolucao',
                ),
              ),
            ).then((_) => reload()),
            icon: Icon(Icons.assignment_return_outlined),
          ),
        if (widget.lote['status'] == 'aberta')
          IconButton(
            tooltip: 'Fechar/trocar remessa',
            onPressed: fechar,
            icon: Icon(Icons.inventory_2_outlined),
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
                    Text('Mercadoria: ${_money(data['valor_recebido_real'])}'),
                    Text('Vendido: ${_money(data['valor_vendido_real'])}'),
                    Text('Em posse: ${_money(data['valor_posse_real'])}'),
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
                return Center(child: CircularProgressIndicator());
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
                      leading: piece['status'] == 'disponivel'
                          ? Checkbox(
                              value: selecionadas.contains(piece['id']),
                              onChanged: (selected) => setState(() {
                                final id = piece['id'] as String;
                                selected == true
                                    ? selecionadas.add(id)
                                    : selecionadas.remove(id);
                              }),
                            )
                          : null,
                      title: Text(
                        '${piece['codigo_exclusivo']} • ${piece['nome']}',
                      ),
                      subtitle: Text(
                        '${piece['status']} • ${_money(piece['preco'])}',
                      ),
                      onTap: piece['status'] == 'vendida'
                          ? () => acaoVenda(piece, 'view')
                          : null,
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
                          : piece['status'] == 'vendida'
                          ? PopupMenuButton<String>(
                              onSelected: (value) => acaoVenda(piece, value),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'view',
                                  child: Text('Ver venda'),
                                ),
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Editar venda'),
                                ),
                                PopupMenuItem(
                                  value: 'refund',
                                  child: Text('Devolver/Estornar'),
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
        if (selecionadas.isNotEmpty)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: finalizarComanda,
                icon: Icon(Icons.receipt_long_outlined),
                label: Text('Finalizar comanda (${selecionadas.length} peças)'),
              ),
            ),
          ),
      ],
    ),
  );

  static String _money(Object? value) =>
      AppFormatters.moeda(value is num ? value.toDouble() : 0);
}
