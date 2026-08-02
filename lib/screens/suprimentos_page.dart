import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/utils/id_generator.dart';
import '../integrations/marketplace_provider.dart';
import '../models/domain/loja.dart';
import '../repositories/compras_repository.dart';
import '../repositories/consignacao_repository.dart';
import '../repositories/loja_repository.dart';
import '../services/session_controller.dart';
import 'barcode_scanner_page.dart';

double _numero(String valor) =>
    double.tryParse(valor.replaceAll(',', '.')) ?? 0;

class FornecedoresPage extends StatefulWidget {
  const FornecedoresPage({super.key});
  @override
  State<FornecedoresPage> createState() => _FornecedoresPageState();
}

class _FornecedoresPageState extends State<FornecedoresPage> {
  final repo = LojaRepository();
  late Future<List<FornecedorLoja>> future;
  @override
  void initState() {
    super.initState();
    future = repo.listarFornecedores();
  }

  void carregar() => setState(() => future = repo.listarFornecedores());
  Future<void> abrir([FornecedorLoja? f]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FornecedorFormPage(fornecedor: f)),
    );
    carregar();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Fornecedores')),
    floatingActionButton: FloatingActionButton.extended(
      heroTag: null,
      onPressed: () => abrir(),
      icon: const Icon(Icons.add),
      label: const Text('Fornecedor'),
    ),
    body: FutureBuilder<List<FornecedorLoja>>(
      future: future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.data!.isEmpty) {
          return const Center(child: Text('Cadastre o primeiro fornecedor.'));
        }
        return ListView(
          children: snap.data!
              .map(
                (f) => ListTile(
                  leading: CircleAvatar(
                    child: Icon(f.entrega ? Icons.local_shipping : Icons.store),
                  ),
                  title: Text(f.nome),
                  subtitle: Text(
                    '${f.whatsapp ?? f.telefone ?? 'Sem telefone'} • prazo médio ${f.prazoDias} dias${f.ativo ? '' : ' • inativo'}',
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => abrir(f),
                ),
              )
              .toList(),
        );
      },
    ),
  );
}

class FornecedorFormPage extends StatefulWidget {
  final FornecedorLoja? fornecedor;
  const FornecedorFormPage({super.key, this.fornecedor});
  @override
  State<FornecedorFormPage> createState() => _FornecedorFormPageState();
}

class _FornecedorFormPageState extends State<FornecedorFormPage> {
  final form = GlobalKey<FormState>();
  final Map<String, TextEditingController> c = {};
  bool entrega = false, ativo = true, salvando = false;
  TextEditingController x(String k, [String v = '']) =>
      c.putIfAbsent(k, () => TextEditingController(text: v));
  @override
  void initState() {
    super.initState();
    final f = widget.fornecedor;
    entrega = f?.entrega ?? false;
    ativo = f?.ativo ?? true;
    x('nome', f?.nome ?? '');
    x('fantasia', f?.nomeFantasia ?? '');
    x('documento', f?.documento ?? '');
    x('telefone', f?.telefone ?? '');
    x('whatsapp', f?.whatsapp ?? '');
    x('email', f?.email ?? '');
    x('endereco', f?.endereco ?? '');
    x('contato', f?.contato ?? '');
    x('prazo', '${f?.prazoDias ?? 0}');
    x('pagamento', f?.formasPagamento ?? '');
    x('minimo', '${f?.minimoPedido ?? 0}');
    x('regioes', f?.regioes ?? '');
    x('obs', f?.observacoes ?? '');
  }

  Widget campo(
    String k,
    String l, {
    bool req = false,
    bool num = false,
    int linhas = 1,
  }) => TextFormField(
    controller: x(k),
    keyboardType: num ? TextInputType.number : TextInputType.text,
    maxLines: linhas,
    validator: req
        ? (v) => (v ?? '').trim().isEmpty ? 'Obrigatório' : null
        : null,
    decoration: InputDecoration(labelText: l),
  );
  Future<void> salvar() async {
    if (!form.currentState!.validate()) return;
    setState(() => salvando = true);
    try {
      await LojaRepository().salvarFornecedor(
        FornecedorLoja(
          id: widget.fornecedor?.id ?? IdGenerator.temporal(),
          comercioId: SessionController.instance.usuario!.comercioId,
          nome: x('nome').text,
          nomeFantasia: x('fantasia').text,
          documento: x('documento').text,
          telefone: x('telefone').text,
          whatsapp: x('whatsapp').text,
          email: x('email').text,
          endereco: x('endereco').text,
          contato: x('contato').text,
          prazoDias: int.tryParse(x('prazo').text) ?? 0,
          formasPagamento: x('pagamento').text,
          minimoPedido: _numero(x('minimo').text),
          entrega: entrega,
          regioes: x('regioes').text,
          observacoes: x('obs').text,
          ativo: ativo,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => salvando = false);
    }
  }

  @override
  void dispose() {
    for (final i in c.values) {
      i.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.fornecedor == null ? 'Novo fornecedor' : 'Editar fornecedor',
      ),
    ),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          campo('nome', 'Nome', req: true),
          campo('fantasia', 'Nome fantasia'),
          campo('documento', 'CPF ou CNPJ'),
          campo('telefone', 'Telefone'),
          campo('whatsapp', 'WhatsApp'),
          campo('email', 'E-mail'),
          campo('endereco', 'Endereço'),
          campo('contato', 'Contato responsável'),
          campo('prazo', 'Prazo médio em dias', num: true),
          campo('pagamento', 'Formas de pagamento'),
          campo('minimo', 'Valor mínimo do pedido', num: true),
          SwitchListTile(
            value: entrega,
            onChanged: (v) => setState(() => entrega = v),
            title: const Text('Entrega disponível'),
          ),
          campo('regioes', 'Regiões atendidas'),
          campo('obs', 'Observações', linhas: 3),
          SwitchListTile(
            value: ativo,
            onChanged: (v) => setState(() => ativo = v),
            title: const Text('Ativo'),
          ),
          FilledButton.icon(
            onPressed: salvando ? null : salvar,
            icon: const Icon(Icons.save),
            label: const Text('Salvar'),
          ),
        ],
      ),
    ),
  );
}

class CentralReposicaoPage extends StatefulWidget {
  const CentralReposicaoPage({super.key});
  @override
  State<CentralReposicaoPage> createState() => _CentralReposicaoPageState();
}

class _CentralReposicaoPageState extends State<CentralReposicaoPage> {
  final repo = LojaRepository();
  late Future<List<Map<String, Object?>>> future;
  @override
  void initState() {
    super.initState();
    future = repo.listarReposicoes();
  }

  void carregar() => setState(() => future = repo.listarReposicoes());
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Central de Reposição'),
      actions: [
        IconButton(onPressed: carregar, icon: const Icon(Icons.refresh)),
      ],
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
                      'Atual ${r['quantidade_atual']} • mínimo ${r['estoque_minimo']}\nDesejado ${r['quantidade_desejada']} • ${r['status']}',
                    ),
                    isThreeLine: true,
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

class ComparadorReposicaoPage extends StatefulWidget {
  final String termoInicial;
  final String? produtoId;
  const ComparadorReposicaoPage({
    super.key,
    this.termoInicial = '',
    this.produtoId,
  });
  @override
  State<ComparadorReposicaoPage> createState() =>
      _ComparadorReposicaoPageState();
}

class _ComparadorReposicaoPageState extends State<ComparadorReposicaoPage> {
  late final TextEditingController termo = TextEditingController(
    text: widget.termoInicial,
  );
  final repo = LojaRepository();
  List<OfertaReposicao> ofertas = [];
  bool carregando = false;
  String ordem = 'total';
  Future<void> pesquisar() async {
    setState(() => carregando = true);
    try {
      final locais = await FornecedorLocalProvider().pesquisar(termo.text);
      final salvas = await repo.listarOfertas(produtoId: widget.produtoId);
      ofertas = [...locais, ...salvas];
      ordenar();
    } finally {
      if (mounted) setState(() => carregando = false);
    }
  }

  void ordenar() {
    ofertas.sort(
      (a, b) => ordem == 'unidade'
          ? a.custoUnitario.compareTo(b.custoUnitario)
          : ordem == 'prazo'
          ? (a.prazoDias ?? 9999).compareTo(b.prazoDias ?? 9999)
          : a.precoTotal.compareTo(b.precoTotal),
    );
    setState(() {});
  }

  Future<void> manual() async {
    final titulo = TextEditingController(text: termo.text),
        preco = TextEditingController(),
        frete = TextEditingController(text: '0'),
        qtd = TextEditingController(text: '1'),
        prazo = TextEditingController(),
        link = TextEditingController();
    String plataforma = 'Fornecedor local';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: const Text('Registrar oferta real'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: plataforma,
                  items: ['Fornecedor local', 'Mercado Livre', 'Shopee']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => setD(() => plataforma = v!),
                ),
                TextField(
                  controller: titulo,
                  decoration: const InputDecoration(labelText: 'Título'),
                ),
                TextField(
                  controller: preco,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Preço'),
                ),
                TextField(
                  controller: frete,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Frete'),
                ),
                TextField(
                  controller: qtd,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantidade da embalagem',
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
    if (ok != true) return;
    final o = ofertaManual(
      plataforma: plataforma,
      titulo: titulo.text,
      preco: _numero(preco.text),
      frete: _numero(frete.text),
      quantidadeEmbalagem: _numero(qtd.text),
      prazoDias: int.tryParse(prazo.text),
      link: link.text,
    );
    await repo.salvarOferta(produtoId: widget.produtoId, oferta: o);
    await pesquisar();
  }

  @override
  void initState() {
    super.initState();
    pesquisar();
  }

  @override
  void dispose() {
    termo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Comparador de Reposição')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: termo,
            decoration: InputDecoration(
              labelText: 'Produto',
              suffixIcon: IconButton(
                onPressed: pesquisar,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              onPressed: () => MercadoLivreProvider().abrirPesquisa(termo.text),
              child: const Text('Mercado Livre'),
            ),
            FilledButton(
              onPressed: () => ShopeeProvider().abrirPesquisa(termo.text),
              child: const Text('Shopee'),
            ),
            OutlinedButton(
              onPressed: manual,
              child: const Text('Registrar oferta'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: DropdownButton<String>(
            value: ordem,
            items: const [
              DropdownMenuItem(
                value: 'total',
                child: Text('Menor preço total'),
              ),
              DropdownMenuItem(
                value: 'unidade',
                child: Text('Menor custo por unidade'),
              ),
              DropdownMenuItem(value: 'prazo', child: Text('Menor prazo')),
            ],
            onChanged: (v) {
              ordem = v!;
              ordenar();
            },
          ),
        ),
        Expanded(
          child: carregando
              ? const Center(child: CircularProgressIndicator())
              : ofertas.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Sem ofertas salvas. Use a pesquisa externa e registre preço, frete e prazo reais. Nenhum resultado é simulado.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: ofertas.length,
                  itemBuilder: (context, i) {
                    final o = ofertas[i];
                    return ListTile(
                      title: Text(o.titulo),
                      subtitle: Text(
                        '${o.plataforma} • total R\$ ${o.precoTotal.toStringAsFixed(2)} • unidade R\$ ${o.custoUnitario.toStringAsFixed(2)}${o.prazoDias == null ? '' : ' • ${o.prazoDias} dias'}',
                      ),
                      trailing: o.link == null
                          ? null
                          : IconButton(
                              onPressed: () =>
                                  PesquisaExternaProviderAbridor.abrir(o.link!),
                              icon: const Icon(Icons.open_in_new),
                            ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

abstract final class PesquisaExternaProviderAbridor {
  static Future<bool> abrir(String link) {
    final p = MercadoLivreProvider();
    return p.abrirOferta(link);
  }
}

class CriarOrdemPage extends StatefulWidget {
  final String? produtoId;
  final double? quantidade;
  const CriarOrdemPage({super.key, this.produtoId, this.quantidade});
  @override
  State<CriarOrdemPage> createState() => _CriarOrdemPageState();
}

class _CriarOrdemPageState extends State<CriarOrdemPage> {
  final loja = LojaRepository();
  ProdutoLoja? produto;
  FornecedorLoja? fornecedor;
  final qtd = TextEditingController(text: '1'),
      valor = TextEditingController(),
      frete = TextEditingController(text: '0'),
      desconto = TextEditingController(text: '0'),
      obs = TextEditingController();
  List<ProdutoLoja> produtos = [];
  List<FornecedorLoja> fornecedores = [];
  @override
  void initState() {
    super.initState();
    carregar();
  }

  Future<void> carregar() async {
    produtos = await loja.listarProdutos();
    fornecedores = await loja.listarFornecedores(ativos: true);
    if (widget.produtoId != null) {
      produto = produtos.where((p) => p.id == widget.produtoId).firstOrNull;
    }
    qtd.text = '${widget.quantidade ?? 1}';
    valor.text = '${produto?.custo ?? 0}';
    if (mounted) setState(() {});
  }

  Future<void> salvar() async {
    if (produto == null) return;
    try {
      await ComprasRepository().criarOrdem(
        itens: [
          ItemOrdemEntrada(produto!, _numero(qtd.text), _numero(valor.text)),
        ],
        fornecedorId: fornecedor?.id,
        frete: _numero(frete.text),
        desconto: _numero(desconto.text),
        observacoes: obs.text,
      );
      if (mounted) Navigator.pop(context);
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
    appBar: AppBar(title: const Text('Nova ordem de compra')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<ProdutoLoja>(
          initialValue: produto,
          decoration: const InputDecoration(labelText: 'Produto'),
          items: produtos
              .map((p) => DropdownMenuItem(value: p, child: Text(p.nome)))
              .toList(),
          onChanged: (v) => setState(() => produto = v),
        ),
        DropdownButtonFormField<FornecedorLoja>(
          initialValue: fornecedor,
          decoration: const InputDecoration(labelText: 'Fornecedor'),
          items: fornecedores
              .map((f) => DropdownMenuItem(value: f, child: Text(f.nome)))
              .toList(),
          onChanged: (v) => setState(() => fornecedor = v),
        ),
        TextField(
          controller: qtd,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Quantidade'),
        ),
        TextField(
          controller: valor,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Valor unitário'),
        ),
        TextField(
          controller: frete,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Frete'),
        ),
        TextField(
          controller: desconto,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Desconto'),
        ),
        TextField(
          controller: obs,
          decoration: const InputDecoration(labelText: 'Observações'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: salvar,
          child: const Text('Criar para aprovação'),
        ),
      ],
    ),
  );
}

class OrdensCompraPage extends StatefulWidget {
  const OrdensCompraPage({super.key});
  @override
  State<OrdensCompraPage> createState() => _OrdensCompraPageState();
}

class _OrdensCompraPageState extends State<OrdensCompraPage> {
  final repo = ComprasRepository();
  late Future<List<Map<String, Object?>>> future;
  @override
  void initState() {
    super.initState();
    carregar();
  }

  void carregar() => setState(() => future = repo.listarOrdens());
  Future<void> acao(Map<String, Object?> o, String a) async {
    try {
      if (a == 'aprovar') await repo.aprovar(o['id'] as String);
      if (a == 'codigo') {
        if (!mounted) return;
        final codigo = await Navigator.push<String>(
          context,
          MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
        );
        if (codigo == null) return;
        final produto = await LojaRepository().buscarCodigo(codigo);
        if (produto == null) {
          throw StateError('Produto do código não encontrado.');
        }
        final itens = await repo.itensOrdem(o['id'] as String);
        final correspondentes = itens.where(
          (i) =>
              i['produto_id'] == produto.id &&
              (i['quantidade_recebida'] as num).toDouble() <
                  (i['quantidade'] as num).toDouble(),
        );
        if (correspondentes.isEmpty) {
          throw StateError(
            'Produto não pertence à ordem ou já foi recebido por completo.',
          );
        }
        await repo.receber(o['id'] as String, {
          correspondentes.first['id'] as String: 1,
        });
      }
      if (a == 'compartilhar') {
        final texto =
            'Ordem ${o['numero']} - Total R\$ ${(o['total'] as num).toStringAsFixed(2)} - Status ${o['status']}';
        final uri = Uri.https('wa.me', '/', {'text': texto});
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      if (a == 'receber') {
        final itens = await repo.itensOrdem(o['id'] as String);
        if (!mounted) return;
        final quantidades = <String, double>{};
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Conferir recebimento'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: itens.map((i) {
                  final c = TextEditingController(
                    text:
                        '${(i['quantidade'] as num).toDouble() - (i['quantidade_recebida'] as num).toDouble()}',
                  );
                  return TextField(
                    controller: c,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: i['produto_nome'] as String,
                    ),
                    onChanged: (v) =>
                        quantidades[i['id'] as String] = _numero(v),
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Receber'),
              ),
            ],
          ),
        );
        if (ok == true) {
          for (final i in itens) {
            quantidades.putIfAbsent(
              i['id'] as String,
              () =>
                  ((i['quantidade'] as num).toDouble() -
                  (i['quantidade_recebida'] as num).toDouble()),
            );
          }
          await repo.receber(o['id'] as String, quantidades);
        }
      }
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
    appBar: AppBar(title: const Text('Ordens de compra')),
    floatingActionButton: FloatingActionButton(
      heroTag: null,
      onPressed: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CriarOrdemPage()),
        );
        carregar();
      },
      child: const Icon(Icons.add),
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.data!.isEmpty) {
          return const Center(child: Text('Nenhuma ordem.'));
        }
        return ListView(
          children: snap.data!
              .map(
                (o) => ListTile(
                  title: Text(
                    '${o['numero']} • R\$ ${(o['total'] as num).toStringAsFixed(2)}',
                  ),
                  subtitle: Text(
                    '${o['fornecedor_nome'] ?? 'Sem fornecedor'} • ${o['status']}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (a) => acao(o, a),
                    itemBuilder: (_) => [
                      if (o['status'] == 'aguardando_aprovacao')
                        const PopupMenuItem(
                          value: 'aprovar',
                          child: Text('Aprovar'),
                        ),
                      if (!['cancelado', 'recebido'].contains(o['status']))
                        const PopupMenuItem(
                          value: 'codigo',
                          child: Text('Conferir 1 por código'),
                        ),
                      const PopupMenuItem(
                        value: 'compartilhar',
                        child: Text('Compartilhar no WhatsApp'),
                      ),
                      if (!['cancelado', 'recebido'].contains(o['status']))
                        const PopupMenuItem(
                          value: 'receber',
                          child: Text('Receber/conferir'),
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

class ConsignacoesPage extends StatefulWidget {
  const ConsignacoesPage({super.key});
  @override
  State<ConsignacoesPage> createState() => _ConsignacoesPageState();
}

class _ConsignacoesPageState extends State<ConsignacoesPage> {
  final repo = ConsignacaoRepository();
  late Future<List<Map<String, Object?>>> future;
  @override
  void initState() {
    super.initState();
    carregar();
  }

  void carregar() => setState(() => future = repo.listar());
  Future<void> nova() async {
    final loja = LojaRepository();
    final fs = await loja.listarFornecedores(ativos: true),
        ps = await loja.listarProdutos();
    if (!mounted) return;
    FornecedorLoja? f;
    ProdutoLoja? p;
    final q = TextEditingController(text: '1'),
        rep = TextEditingController(),
        preco = TextEditingController(),
        perc = TextEditingController(text: '30'),
        lote = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: const Text('Receber consignação'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<FornecedorLoja>(
                  decoration: const InputDecoration(labelText: 'Fornecedor'),
                  items: fs
                      .map(
                        (x) => DropdownMenuItem(value: x, child: Text(x.nome)),
                      )
                      .toList(),
                  onChanged: (v) => setD(() => f = v),
                ),
                DropdownButtonFormField<ProdutoLoja>(
                  decoration: const InputDecoration(labelText: 'Produto'),
                  items: ps
                      .map(
                        (x) => DropdownMenuItem(value: x, child: Text(x.nome)),
                      )
                      .toList(),
                  onChanged: (v) => setD(() => p = v),
                ),
                TextField(
                  controller: q,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantidade recebida',
                  ),
                ),
                TextField(
                  controller: rep,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Repasse unitário',
                  ),
                ),
                TextField(
                  controller: preco,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Preço de venda',
                  ),
                ),
                TextField(
                  controller: perc,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Percentual do salão',
                  ),
                ),
                TextField(
                  controller: lote,
                  decoration: const InputDecoration(labelText: 'Lote/coleção'),
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
              onPressed: f == null || p == null
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Receber'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await repo.receber(
        fornecedorId: f!.id,
        produtoId: p!.id,
        quantidade: _numero(q.text),
        repasse: _numero(rep.text),
        precoVenda: _numero(preco.text),
        percentualSalao: _numero(perc.text),
        lote: lote.text,
      );
      carregar();
    }
  }

  Future<void> resumo(Map<String, Object?> c) async {
    final r = await repo.resumo(c['id'] as String);
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fechamento da consignação'),
        content: Text(
          'Recebidos: ${r.recebidos}\nVendidos: ${r.vendidos}\nDisponíveis: ${r.disponiveis}\nDevolvidos: ${r.devolvidos}\nFaturamento: R\$ ${r.faturamento.toStringAsFixed(2)}\nValor do salão: R\$ ${r.valorSalao.toStringAsFixed(2)}\nDevido ao fornecedor: R\$ ${r.valorFornecedor.toStringAsFixed(2)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Voltar'),
          ),
          if (c['status'] == 'aberta')
            FilledButton(
              onPressed: () async {
                await repo.fechar(c['id'] as String);
                if (context.mounted) Navigator.pop(context);
                carregar();
              },
              child: const Text('Fechar consignação'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Consignações')),
    floatingActionButton: FloatingActionButton.extended(
      heroTag: null,
      onPressed: nova,
      icon: const Icon(Icons.add),
      label: const Text('Receber'),
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.data!.isEmpty) {
          return const Center(child: Text('Nenhuma consignação.'));
        }
        return ListView(
          children: snap.data!
              .map(
                (c) => ListTile(
                  title: Text(
                    '${c['fornecedor_nome']} • ${c['lote_colecao'] ?? 'Sem lote'}',
                  ),
                  subtitle: Text('${c['status']} • ${c['recebida_em']}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => resumo(c),
                ),
              )
              .toList(),
        );
      },
    ),
  );
}
