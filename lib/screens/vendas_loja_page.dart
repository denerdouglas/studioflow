import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/domain/acesso.dart';
import '../models/domain/loja.dart';
import '../repositories/cliente_repository.dart';
import '../repositories/comanda_loja_repository.dart';
import '../repositories/loja_repository.dart';
import '../services/session_controller.dart';
import '../models/domain/scanner_product_draft.dart';
import '../widgets/cliente_search_selector.dart';
import '../widgets/produto_search_selector.dart';
import 'vision_scanner_page.dart';

class VendasLojaPage extends StatefulWidget {
  const VendasLojaPage({super.key});
  @override
  State<VendasLojaPage> createState() => _VendasLojaPageState();
}

class _VendasLojaPageState extends State<VendasLojaPage> {
  final repo = LojaRepository();
  final comandas = ComandaLojaRepository();
  final List<ItemCarrinho> itens = [];
  final desconto = TextEditingController(text: '0');
  String pagamento = 'Pix';
  String situacaoPagamento = 'Pago';
  DateTime dataPagamento = DateTime.now();
  DateTime? vencimento;
  bool finalizando = false;
  ClienteRegistro? cliente;

  double get subtotal => itens.fold(0, (v, i) => v + i.total);
  double get descontoValor =>
      double.tryParse(desconto.text.replaceAll(',', '.')) ?? 0;
  double get total => subtotal - descontoValor;

  void adicionar(ProdutoLoja p) {
    if (p.tipo == 'peca_unica') {
      if (itens.any((x) => x.produto.id == p.id)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Peça única já adicionada ao carrinho.'),
          ),
        );
        return;
      }
    }
    final i = itens.indexWhere((x) => x.produto.id == p.id);
    setState(() {
      if (i < 0) {
        if (p.tipo != 'peca_unica' && p.quantidadeAtual < 1) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Estoque insuficiente para este produto.'),
            ),
          );
          return;
        }
        itens.add(ItemCarrinho(p, 1));
      } else {
        if (p.tipo != 'peca_unica' &&
            p.quantidadeAtual < itens[i].quantidade + 1) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Estoque insuficiente para adicionar mais deste produto.',
              ),
            ),
          );
          return;
        }
        itens[i] = ItemCarrinho(p, itens[i].quantidade + 1);
      }
    });
  }

  Future<void> selecionarProduto() async {
    final p = await showModalBottomSheet<ProdutoLoja>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const ProdutoSearchSelector(),
    );
    if (p != null) adicionar(p);
  }

  Future<void> selecionarCliente() async {
    final escolhido = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const ClienteSearchSelector(),
    );
    if (!mounted || escolhido == null) return;
    if (escolhido == 'sem_cliente') {
      setState(() => cliente = null);
    } else if (escolhido is ClienteRegistro) {
      setState(() => cliente = escolhido);
    }
  }

  Future<Map<String, double>?> obterPagamentos() async {
    if (pagamento != 'Misto') return {pagamento.toLowerCase(): total};
    final pix = TextEditingController();
    final dinheiro = TextEditingController();
    final cartao = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Pagamento misto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Total: R\$ ${total.toStringAsFixed(2)}'),
            TextField(
              controller: pix,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Pix'),
            ),
            TextField(
              controller: dinheiro,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Dinheiro'),
            ),
            TextField(
              controller: cartao,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Cartão'),
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
            child: Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok != true) return null;
    return {
      if (_valorPagamento(pix.text) > 0) 'pix': _valorPagamento(pix.text),
      if (_valorPagamento(dinheiro.text) > 0)
        'dinheiro': _valorPagamento(dinheiro.text),
      if (_valorPagamento(cartao.text) > 0)
        'cartao': _valorPagamento(cartao.text),
    };
  }

  double _valorPagamento(String valor) =>
      double.tryParse(valor.replaceAll(',', '.')) ?? 0;

  String _formatDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';

  String _formatDateTime(DateTime value) =>
      '${_formatDate(value)} às '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  Future<void> _selectPaymentDate() async {
    final day = await showDatePicker(
      context: context,
      initialDate: dataPagamento,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(dataPagamento),
    );
    if (time == null) return;
    setState(
      () => dataPagamento = DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _selectDueDate() async {
    final day = await showDatePicker(
      context: context,
      initialDate: vencimento ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (day != null) setState(() => vencimento = day);
  }

  Future<void> ler() async {
    final result = await Navigator.push<ScannerResult?>(
      context,
      MaterialPageRoute(builder: (_) => const VisionScannerPage()),
    );
    if (result == null) return;

    if (result.tipo == ScannerResultType.cancelado) return;
    if (result.tipo == ScannerResultType.produtoExistente ||
        result.tipo == ScannerResultType.produtoNovo) {
      if (result.produto != null) {
        adicionar(result.produto);
        return;
      }
    }

    final codigo =
        result.draft?.referenciaComercial?.value ?? result.draft?.gtin?.value;
    if (codigo == null) return;

    try {
      final p = await repo.buscarCodigo(codigo);
      if (p == null) throw StateError('Produto não encontrado para venda.');
      adicionar(p);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> finalizar() async {
    Map<String, double>? pagamentos;
    if (situacaoPagamento == 'Pago') {
      pagamentos = await obterPagamentos();
      if (pagamentos == null) return;
    } else {
      if (cliente == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Vincule um cliente para criar a conta a receber pendente.',
            ),
          ),
        );
        return;
      }
      if (vencimento == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Informe o vencimento.')));
        return;
      }
    }
    setState(() => finalizando = true);
    try {
      late final String id;
      if (situacaoPagamento == 'Pago') {
        id = await repo.finalizarVenda(
          itens: itens,
          desconto: descontoValor,
          pagamentos: pagamentos!,
          clienteId: cliente?.id,
          profissionalId: SessionController.instance.usuario?.id ?? 'prof_1',
          dataPagamento: dataPagamento,
        );
      } else {
        id = await comandas.criar(
          clienteId: cliente!.id,
          vencimento: vencimento,
        );
        await comandas.reconciliarItens(
          id,
          itens
              .map(
                (item) => <String, Object?>{
                  'produto_id': item.produto.id,
                  'nome': item.produto.nome,
                  'codigo': item.produto.codigoBarras,
                  'quantidade': item.quantidade,
                  'valor_unitario': item.produto.precoVenda,
                  'desconto': 0.0,
                },
              )
              .toList(),
          desconto: descontoValor,
        );
        await comandas.finalizar(
          id,
          pagamentoInicial: 0,
          formaPagamento: pagamento,
          vencimento: vencimento,
        );
      }
      if (!mounted) return;
      final resumo =
          'StudioFlow - Venda $id\n${itens.map((i) => '${i.quantidade}x ${i.produto.nome} - R\$ ${i.total.toStringAsFixed(2)}').join('\n')}\nTotal: R\$ ${total.toStringAsFixed(2)}\nSituação: $situacaoPagamento\nPagamento: $pagamento';
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Venda concluída'),
          content: SelectableText(resumo),
          actions: [
            TextButton(
              onPressed: () => launchUrl(
                Uri.https('wa.me', '/', {'text': resumo}),
                mode: LaunchMode.externalApplication,
              ),
              child: Text('Enviar pelo WhatsApp'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Concluir'),
            ),
          ],
        ),
      );
      setState(() {
        itens.clear();
        desconto.text = '0';
        cliente = null;
        situacaoPagamento = 'Pago';
        dataPagamento = DateTime.now();
        vencimento = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => finalizando = false);
    }
  }

  @override
  void dispose() {
    desconto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Nova venda'),
      actions: [IconButton(onPressed: ler, icon: Icon(Icons.barcode_reader))],
    ),
    body: Column(
      children: [
        Expanded(
          child: itens.isEmpty
              ? Center(
                  child: Text(
                    'Carrinho vazio. Adicione por nome ou código de barras.',
                  ),
                )
              : ListView.builder(
                  itemCount: itens.length,
                  itemBuilder: (context, index) {
                    final item = itens[index];
                    return ListTile(
                      title: Text(item.produto.nome),
                      subtitle: Text(
                        '${item.quantidade} × R\$ ${item.produto.precoVenda.toStringAsFixed(2)} = R\$ ${item.total.toStringAsFixed(2)}',
                      ),
                      leading: IconButton(
                        onPressed: () => setState(() {
                          if (item.quantidade <= 1) {
                            itens.removeAt(index);
                          } else {
                            itens[index] = ItemCarrinho(
                              item.produto,
                              item.quantidade - 1,
                            );
                          }
                        }),
                        icon: Icon(Icons.remove_circle_outline),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () {
                              if (item.produto.tipo == 'peca_unica') {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Não é possível aumentar a quantidade de uma peça única.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              if (item.quantidade + 1 >
                                  item.produto.quantidadeAtual) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Estoque insuficiente.'),
                                  ),
                                );
                                return;
                              }
                              setState(
                                () => itens[index] = ItemCarrinho(
                                  item.produto,
                                  item.quantidade + 1,
                                ),
                              );
                            },
                            icon: Icon(Icons.add_circle_outline),
                          ),
                          IconButton(
                            onPressed: () =>
                                setState(() => itens.removeAt(index)),
                            icon: Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.person_outline),
                    title: Text(
                      cliente?.nome ?? 'Selecionar cliente (opcional)',
                    ),
                    subtitle: Text(
                      cliente?.whatsapp ?? 'Toque para vincular a venda',
                    ),
                    trailing: Icon(Icons.chevron_right),
                    onTap: selecionarCliente,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: desconto,
                          enabled: SessionController.instance.usuario!.podeAcao(
                            AcaoPermissao.aplicarDesconto,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Desconto R\$',
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: pagamento,
                          decoration: const InputDecoration(
                            labelText: 'Pagamento',
                          ),
                          items: ['Pix', 'Dinheiro', 'Cartão', 'Misto']
                              .map(
                                (v) =>
                                    DropdownMenuItem(value: v, child: Text(v)),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => pagamento = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: situacaoPagamento,
                    decoration: const InputDecoration(
                      labelText: 'Situação do pagamento',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Pago', child: Text('Pago')),
                      DropdownMenuItem(
                        value: 'Pendente',
                        child: Text('Pendente'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => situacaoPagamento = value ?? 'Pago'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      situacaoPagamento == 'Pago'
                          ? 'Data do pagamento'
                          : 'Data de vencimento',
                    ),
                    subtitle: Text(
                      situacaoPagamento == 'Pago'
                          ? _formatDateTime(dataPagamento)
                          : vencimento == null
                          ? 'Selecionar vencimento'
                          : _formatDate(vencimento!),
                    ),
                    trailing: const Icon(Icons.calendar_month_outlined),
                    onTap: situacaoPagamento == 'Pago'
                        ? _selectPaymentDate
                        : _selectDueDate,
                  ),
                  SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'R\$ ${total.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: selecionarProduto,
                          icon: Icon(Icons.search),
                          label: Text('Adicionar'),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: itens.isEmpty || finalizando
                              ? null
                              : finalizar,
                          icon: Icon(Icons.check),
                          label: Text('Finalizar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class HistoricoVendasPage extends StatefulWidget {
  final bool somenteEstornos;
  const HistoricoVendasPage({super.key, this.somenteEstornos = false});
  @override
  State<HistoricoVendasPage> createState() => _HistoricoVendasPageState();
}

class _HistoricoVendasPageState extends State<HistoricoVendasPage> {
  final repo = LojaRepository();
  final pesquisa = TextEditingController();
  late Future<List<Map<String, Object?>>> future;
  @override
  void initState() {
    super.initState();
    future = repo.listarVendas();
  }

  void carregar() => setState(() => future = repo.listarVendas());

  @override
  void dispose() {
    pesquisa.dispose();
    super.dispose();
  }

  Future<void> cancelar(Map<String, Object?> venda) async {
    await detalhe(venda);
    if (!mounted) return;
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancelar venda?'),
        content: TextField(
          controller: motivo,
          decoration: const InputDecoration(labelText: 'Motivo obrigatório'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Cancelar venda'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await repo.cancelarVenda(venda['id'] as String, motivo.text);
      carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> detalhe(Map<String, Object?> venda) async {
    final detail = await repo.detalheVenda(venda['id'] as String);
    if (!mounted) return;
    final items = detail['itens'] as List<Map<String, Object?>>;
    final payments = detail['pagamentos'] as List<Map<String, Object?>>;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Venda ${venda['numero']}'),
        content: SingleChildScrollView(
          child: Text(
            'Cliente: ${detail['cliente_nome'] ?? 'Não informado'}\n'
            'Data: ${detail['data_venda']}\n'
            'Responsável: ${detail['profissional_nome'] ?? detail['profissional_id']}\n\n'
            'Itens:\n${items.map((item) => '${item['quantidade']}x ${item['nome']} (${item['codigo'] ?? 'sem código'}) • R\$ ${item['valor_unitario']}').join('\n')}\n\n'
            'Pagamentos:\n${payments.map((payment) => '${payment['forma_pagamento']} • R\$ ${payment['valor']} • ${payment['status']}').join('\n')}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Fechar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.somenteEstornos ? 'Estornos' : 'Histórico de vendas'),
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return Center(child: CircularProgressIndicator());
        }
        final query = pesquisa.text.trim().toLowerCase();
        final sales = snap.data!.where((sale) {
          if (widget.somenteEstornos &&
              !['cancelada', 'estornada'].contains(sale['status'])) {
            return false;
          }
          return query.isEmpty ||
              sale.values.any(
                (value) => '$value'.toLowerCase().contains(query),
              );
        }).toList();
        if (sales.isEmpty && query.isEmpty) {
          return Center(child: Text('Nenhuma venda registrada.'));
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: pesquisa,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Pesquisar cliente, data, produto ou código',
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: sales
                    .map(
                      (v) => ListTile(
                        title: Text(
                          '${v['numero']} • R\$ ${(v['total'] as num).toStringAsFixed(2)}',
                        ),
                        subtitle: Text('${v['status']} • ${v['criada_em']}'),
                        onTap: () => detalhe(v),
                        trailing:
                            v['status'] == 'concluida' &&
                                SessionController.instance.usuario!.podeAcao(
                                  AcaoPermissao.cancelarVenda,
                                )
                            ? IconButton(
                                onPressed: () => cancelar(v),
                                icon: Icon(Icons.cancel_outlined),
                              )
                            : null,
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        );
      },
    ),
  );
}
