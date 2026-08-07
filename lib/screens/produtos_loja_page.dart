import 'package:flutter/material.dart';

import '../core/utils/id_generator.dart';
import '../models/domain/acesso.dart';
import '../models/domain/loja.dart';
import '../models/domain/scanner_product_draft.dart';
import '../repositories/loja_repository.dart';
import '../services/product_lookup_service.dart';
import '../services/session_controller.dart';
import 'vision_scanner_page.dart';
import 'estoque_page.dart';

class ProdutosLojaPage extends StatefulWidget {
  final bool somenteBaixo;
  final ModalidadeProduto? modalidade;
  final bool somenteUsoInterno;
  final bool somenteAtivos;
  
  const ProdutosLojaPage({
    super.key,
    this.somenteBaixo = false,
    this.modalidade,
    this.somenteUsoInterno = false,
    this.somenteAtivos = false,
  });

  @override
  State<ProdutosLojaPage> createState() => _ProdutosLojaPageState();
}

class _ProdutosLojaPageState extends State<ProdutosLojaPage> {
  final _repo = LojaRepository();
  final _lookup = ProductLookupService();
  final _busca = TextEditingController();
  late Future<List<ProdutoLoja>> _future;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  void _carregar() => _future = _repo.listarProdutos(
    pesquisa: _busca.text,
    somenteBaixo: widget.somenteBaixo,
    modalidade: widget.modalidade,
    somenteUsoInterno: widget.somenteUsoInterno,
    somenteAtivos: widget.somenteAtivos,
    incluirInativos: true,
  );

  Future<void> _abrir([
    ProdutoLoja? produto,
    String? codigo,
    CatalogProduct? catalogProduct,
    bool productNotFound = false,
  ]) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ProdutoFormPage(
          produto: produto,
          codigoInicial: codigo,
          catalogProduct: catalogProduct,
          productNotFound: productNotFound,
        ),
      ),
    );
    setState(_carregar);
  }

  Future<void> _lerCodigo() async {
    final codigo = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const VisionScannerPage()),
    );
    if (!mounted || codigo == null) return;
    try {
      final produto = await _repo.buscarCodigo(codigo);
      if (!mounted) return;
      if (produto == null) {
        final result = await _lookup.lookup(
          codigo,
          commerceId: SessionController.instance.usuario!.comercioId,
        );
        if (!mounted) return;
        final found = result.product;
        if (found?.localProductId != null &&
            found?.localDestination == 'salao') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Produto já cadastrado no estoque do salão.'),
            ),
          );
          await Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => const EstoquePage()),
          );
        } else {
          await _abrir(null, result.normalizedGtin, found, found == null);
        }
      } else {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProdutoDetalhePage(produtoId: produto.id),
          ),
        );
        setState(_carregar);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final titulo = widget.somenteBaixo
        ? 'Estoque baixo'
        : widget.modalidade == ModalidadeProduto.consignado
        ? 'Produtos consignados'
        : 'Produtos da loja';
    return Scaffold(
      appBar: AppBar(
        title: Text(titulo),
        actions: [
          IconButton(
            onPressed: _lerCodigo,
            icon: const Icon(Icons.barcode_reader),
          ),
        ],
      ),
      floatingActionButton:
          SessionController.instance.usuario!.podeAcao(
            AcaoPermissao.cadastrarProduto,
          )
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () => _abrir(),
              icon: const Icon(Icons.add),
              label: const Text('Produto'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _busca,
              onSubmitted: (_) => setState(_carregar),
              decoration: InputDecoration(
                hintText: 'Nome, marca ou código',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: () => setState(_carregar),
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<ProdutoLoja>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('${snapshot.error}'));
                }
                final itens = snapshot.data ?? const [];
                if (itens.isEmpty) {
                  return const Center(
                    child: Text('Nenhum produto encontrado.'),
                  );
                }
                final categorias = <String, List<ProdutoLoja>>{};
                for (final p in itens) {
                  categorias.putIfAbsent(p.categoria, () => []).add(p);
                }

                final sortedCategories = categorias.keys.toList()..sort();

                return RefreshIndicator(
                  onRefresh: () async => setState(_carregar),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: sortedCategories.length,
                    itemBuilder: (context, i) {
                      final cat = sortedCategories[i];
                      final catItens = categorias[cat]!;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                            child: Text(
                              cat,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                            ),
                          ),
                          ...catItens.map(
                            (p) => Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              color: p.estoqueBaixo
                                  ? Colors.orange.shade50
                                  : null,
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Icon(
                                    p.modalidade == ModalidadeProduto.consignado
                                        ? Icons.handshake
                                        : Icons.shopping_bag,
                                  ),
                                ),
                                title: Text(
                                  '${p.nome}${p.tipoProduto == 'uso_interno' ? ' (NÃO DESTINADO À VENDA)' : ''}${p.tipoProduto == 'ambos' ? ' (POSSUI SALDO COMERCIAL)' : ''}',
                                  style: TextStyle(
                                    color: p.tipoProduto == 'uso_interno' ? Colors.red : null,
                                    fontWeight: p.tipoProduto == 'uso_interno' ? FontWeight.bold : null,
                                  ),
                                ),
                                subtitle: Text(
                                  '${p.quantidadeAtual.toStringAsFixed(2)} ${p.unidade}\nR\$ ${p.precoVenda.toStringAsFixed(2)}${p.ativo ? '' : '   Inativo'}',
                                ),
                                isThreeLine: true,
                                trailing: p.estoqueBaixo
                                    ? const Icon(
                                        Icons.warning_amber,
                                        color: Colors.orange,
                                      )
                                    : const Icon(Icons.chevron_right),
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ProdutoDetalhePage(produtoId: p.id),
                                    ),
                                  );
                                  setState(_carregar);
                                },
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}


class ProdutoFormPage extends StatefulWidget {
  final ProdutoLoja? produto;
  final String? codigoInicial;
  final ScannerProductDraft? draftInicial;
  final String? finalidadeInicial;
  final CatalogProduct? catalogProduct;
  final bool productNotFound;
  const ProdutoFormPage({
    super.key,
    this.produto,
    this.codigoInicial,
    this.draftInicial,
    this.finalidadeInicial,
    this.catalogProduct,
    this.productNotFound = false,
  });
  @override
  State<ProdutoFormPage> createState() => _ProdutoFormPageState();
}

class _ProdutoFormPageState extends State<ProdutoFormPage> {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> c = {};
  ModalidadeProduto modalidade = ModalidadeProduto.proprio;
  bool ativo = true;
  bool revisaoModelagemEstoque = false;
  bool salvando = false;
  bool consultandoCodigo = false;
  late String origemCatalogo;

  TextEditingController _c(String key, [String value = '']) =>
      c.putIfAbsent(key, () => TextEditingController(text: value));
  double _n(String key) =>
      double.tryParse(_c(key).text.replaceAll(',', '.')) ?? 0;

  @override
  void initState() {
    super.initState();
    final p = widget.produto;
    final catalog = widget.catalogProduct;
    origemCatalogo = p?.origemCatalogo ?? catalog?.source ?? 'manual';
    modalidade = p?.modalidade ?? ModalidadeProduto.proprio;
    ativo = p?.ativo ?? true;
    revisaoModelagemEstoque = p?.revisaoModelagemEstoque ?? false;
    _c('nome', widget.produto?.nome ?? widget.catalogProduct?.name ?? widget.draftInicial?.nome?.value ?? '');
    _c('descricao', widget.produto?.descricao ?? widget.catalogProduct?.description ?? widget.draftInicial?.descricao?.value ?? '');
    _c('categoria', widget.produto?.categoria ?? widget.catalogProduct?.category ?? widget.draftInicial?.categoriaSugerida?.value ?? 'Cosméticos');
    _c('marca', widget.produto?.marca ?? widget.catalogProduct?.brand ?? widget.draftInicial?.marca?.value ?? '');
    _c('interno', p?.codigoInterno ?? '');
    _c('barras', p?.codigoBarras ?? widget.codigoInicial ?? widget.catalogProduct?.gtin ?? widget.draftInicial?.gtin?.value ?? '');
    _c('tipo', p?.tipo ?? 'produto');
    _c('custo', p?.custo.toStringAsFixed(2) ?? '0');
    _c('preco', p?.precoVenda.toStringAsFixed(2) ?? '0');
    _c('quantidade', p?.quantidadeAtual.toString() ?? '0');
    _c('minimo', p?.estoqueMinimo.toString() ?? '0');
    _c('sugerida', p?.quantidadeSugerida.toString() ?? '0');
    _c('unidade', p?.unidade ?? catalog?.physicalUnit ?? widget.draftInicial?.unidade?.value ?? 'un');
    _c(
      'conteudo',
      p?.conteudoPorUnidade.toString() ??
          catalog?.contentPerUnit?.toString() ??
          '1',
    );
    _c('unidade_conteudo', p?.unidadeConteudo ?? catalog?.contentUnit ?? 'g');
    _c('embalagem', p?.quantidadeEmbalagem.toString() ?? '1');
    _c('lote', p?.lote ?? '');
    _c('validade', p?.validade?.toIso8601String().split('T').first ?? '');
    _c('imagem', p?.imagem ?? catalog?.imageUrl ?? '');
    _c('observacoes', p?.observacoes ?? '');
  }

  Future<void> _scan() async {
    final codigo = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const VisionScannerPage()),
    );
    if (!mounted || codigo == null) return;
    setState(() => consultandoCodigo = true);
    try {
      final existente = await LojaRepository().buscarCodigo(codigo);
      if (!mounted) return;
      if (existente != null && existente.id != widget.produto?.id) {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => ProdutoDetalhePage(produtoId: existente.id),
          ),
        );
        return;
      }
      final result = await ProductLookupService().lookup(
        codigo,
        commerceId: SessionController.instance.usuario!.comercioId,
      );
      if (!mounted) return;
      final product = result.product;
      if (product?.localProductId != null &&
          product?.localDestination == 'salao') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produto já cadastrado no estoque do salão.'),
          ),
        );
        return;
      }
      setState(() {
        _c('barras').text = result.normalizedGtin;
        if (product != null) {
          if (_c('nome').text.trim().isEmpty) _c('nome').text = product.name;
          if (_c('marca').text.trim().isEmpty) {
            _c('marca').text = product.brand ?? '';
          }
          if (_c('descricao').text.trim().isEmpty) {
            _c('descricao').text = product.description ?? '';
          }
          if (_c('categoria').text.trim().isEmpty ||
              _c('categoria').text == 'Cosméticos') {
            _c('categoria').text = product.category ?? 'Cosméticos';
          }
          if (_c('imagem').text.trim().isEmpty) {
            _c('imagem').text = product.imageUrl ?? '';
          }
          if (_c('unidade').text.trim().isEmpty || _c('unidade').text == 'un') {
            _c('unidade').text = product.physicalUnit ?? 'un';
          }
          if (product.contentPerUnit != null) {
            _c('conteudo').text = product.contentPerUnit.toString();
          }
          if (product.contentUnit != null) {
            _c('unidade_conteudo').text = product.contentUnit!;
          }
          origemCatalogo = product.source;
        } else {
          origemCatalogo = 'manual';
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Produto não encontrado. Complete os dados para cadastrá-lo.',
              ),
            ),
          );
        }
      });
    } on CatalogProviderUnavailable catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao pesquisar o produto: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => consultandoCodigo = false);
    }
  }

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => salvando = true);
    try {
      final agora = DateTime.now();
      final custo = _n('custo'), preco = _n('preco');
      final produto = ProdutoLoja(
        id: widget.produto?.id ?? IdGenerator.temporal(),
        comercioId: SessionController.instance.usuario!.comercioId,
        nome: _c('nome').text,
        tipoProduto: widget.produto?.tipoProduto ?? 'venda',
        descricao: _c('descricao').text,
        categoria: _c('categoria').text,
        marca: _c('marca').text,
        codigoInterno: _c('interno').text,
        codigoBarras: _c('barras').text,
        tipo: _c('tipo').text,
        modalidade: modalidade,
        custo: custo,
        precoVenda: preco,
        margem: preco == 0 ? 0 : ((preco - custo) / preco) * 100,
        quantidadeAtual: widget.produto == null
            ? _n('quantidade')
            : widget.produto!.quantidadeAtual,
        estoqueMinimo: _n('minimo'),
        quantidadeSugerida: _n('sugerida'),
        unidade: _c('unidade').text,
        conteudoPorUnidade: _n('conteudo'),
        unidadeConteudo: _c('unidade_conteudo').text,
        revisaoModelagemEstoque: false,
        quantidadeEmbalagem: _n('embalagem'),
        lote: _c('lote').text,
        dataEntrada: widget.produto?.dataEntrada ?? agora,
        validade: DateTime.tryParse(_c('validade').text),
        imagem: _c('imagem').text,
        observacoes: _c('observacoes').text,
        origemCatalogo: origemCatalogo,
        ativo: ativo,
        criadoEm: widget.produto?.criadoEm ?? agora,
        atualizadoEm: agora,
      );
      await LojaRepository().salvarProduto(produto);
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

  Widget _campo(
    String key,
    String label, {
    bool numero = false,
    int linhas = 1,
    bool obrigatorio = false,
    Widget? suffix,
  }) => TextFormField(
    controller: _c(key),
    keyboardType: numero
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
    maxLines: linhas,
    validator: obrigatorio
        ? (v) => (v ?? '').trim().isEmpty ? 'Campo obrigatório' : null
        : null,
    decoration: InputDecoration(labelText: label, suffixIcon: suffix),
  );

  @override
  void dispose() {
    for (final x in c.values) {
      x.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.produto == null ? 'Novo produto' : 'Editar produto'),
    ),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.productNotFound)
            const Card(
              color: Color(0xFFFFF3CD),
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Produto não encontrado. Complete os dados para cadastrá-lo.',
                ),
              ),
            ),
          if (revisaoModelagemEstoque)
            const Card(
              color: Color(0xFFFFF3CD),
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Revisão necessária: Separe a quantidade física (potes, frascos) do conteúdo (g, ml).',
                  style: TextStyle(
                    color: Color(0xFF856404),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          if (consultandoCodigo) const LinearProgressIndicator(),
          _campo('nome', 'Nome', obrigatorio: true),
          _campo('descricao', 'Descrição', linhas: 2),
          _campo('categoria', 'Categoria', obrigatorio: true),
          _campo('marca', 'Marca'),
          _campo('interno', 'Código interno'),
          _campo(
            'barras',
            'Código de barras',
            suffix: IconButton(
              onPressed: consultandoCodigo ? null : _scan,
              icon: const Icon(Icons.barcode_reader),
            ),
          ),
          _campo('tipo', 'Tipo do produto', obrigatorio: true),
          DropdownButtonFormField<ModalidadeProduto>(
            initialValue: modalidade,
            decoration: const InputDecoration(labelText: 'Modalidade'),
            items: ModalidadeProduto.values
                .map(
                  (m) => DropdownMenuItem(
                    value: m,
                    child: Text(
                      m == ModalidadeProduto.proprio ? 'Próprio' : 'Consignado',
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => modalidade = v!),
          ),
          if (SessionController.instance.usuario!.podeAcao(
            AcaoPermissao.visualizarCusto,
          ))
            Row(
              children: [
                Expanded(child: _campo('custo', 'Custo', numero: true)),
                const SizedBox(width: 12),
                Expanded(
                  child: _campo('preco', 'Preço de venda', numero: true),
                ),
              ],
            )
          else
            _campo('preco', 'Preço de venda', numero: true),
          if (widget.produto == null)
            _campo('quantidade', 'Quantidade inicial', numero: true),
          Row(
            children: [
              Expanded(child: _campo('minimo', 'Estoque mínimo', numero: true)),
              const SizedBox(width: 12),
              Expanded(
                child: _campo('sugerida', 'Reposição sugerida', numero: true),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _campo(
                  'unidade',
                  'Unidade física (pote)',
                  obrigatorio: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _campo('embalagem', 'Qtd. por embalagem', numero: true),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _campo('conteudo', 'Conteúdo (peso/vol)', numero: true),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _campo(
                  'unidade_conteudo',
                  'Unidade do conteúdo (g, ml)',
                ),
              ),
            ],
          ),
          _campo('lote', 'Lote'),
          _campo('validade', 'Validade (AAAA-MM-DD)'),
          _campo('imagem', 'Caminho/URL da imagem'),
          _campo('observacoes', 'Observações', linhas: 3),
          SwitchListTile(
            value: ativo,
            onChanged: (v) => setState(() => ativo = v),
            title: const Text('Produto ativo'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: salvando ? null : _salvar,
            icon: const Icon(Icons.save),
            label: Text(salvando ? 'Salvando...' : 'Salvar produto'),
          ),
        ],
      ),
    ),
  );
}

class ProdutoDetalhePage extends StatefulWidget {
  final String produtoId;
  const ProdutoDetalhePage({super.key, required this.produtoId});
  @override
  State<ProdutoDetalhePage> createState() => _ProdutoDetalhePageState();
}

class _ProdutoDetalhePageState extends State<ProdutoDetalhePage> {
  final repo = LojaRepository();
  late Future<ProdutoLoja?> future;
  @override
  void initState() {
    super.initState();
    future = repo.buscarProduto(widget.produtoId);
  }

  void recarregar() =>
      setState(() => future = repo.buscarProduto(widget.produtoId));

  Future<void> movimentar(ProdutoLoja p) async {
    final qtd = TextEditingController();
    final obs = TextEditingController();
    TipoMovimentoLoja tipo = TipoMovimentoLoja.entradaManual;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Movimentar estoque'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<TipoMovimentoLoja>(
                initialValue: tipo,
                items: TipoMovimentoLoja.values
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                    .toList(),
                onChanged: (v) => setDialog(() => tipo = v!),
              ),
              TextField(
                controller: qtd,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Quantidade'),
              ),
              TextField(
                controller: obs,
                decoration: const InputDecoration(
                  labelText: 'Motivo/observação',
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
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await repo.movimentar(
        produtoId: p.id,
        tipo: tipo,
        quantidade: double.tryParse(qtd.text.replaceAll(',', '.')) ?? 0,
        origem: 'movimentacao_manual',
        observacao: obs.text,
      );
      recarregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ProdutoLoja?>(
    future: future,
    builder: (context, snap) {
      final p = snap.data;
      return Scaffold(
        appBar: AppBar(
          title: Text(p?.nome ?? 'Produto'),
          actions:
              p == null ||
                  !SessionController.instance.usuario!.podeAcao(
                    AcaoPermissao.editarProduto,
                  )
              ? null
              : [
                  IconButton(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProdutoFormPage(produto: p),
                        ),
                      );
                      recarregar();
                    },
                    icon: const Icon(Icons.edit),
                  ),
                ],
        ),
        body: p == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ListTile(
                    title: const Text('Estoque atual'),
                    subtitle: Text('${p.quantidadeAtual} ${p.unidade}'),
                    trailing: p.estoqueBaixo
                        ? const Icon(Icons.warning, color: Colors.orange)
                        : null,
                  ),
                  if (SessionController.instance.usuario!.podeAcao(
                    AcaoPermissao.visualizarCusto,
                  ))
                    ListTile(
                      title: const Text('Preço / custo / margem'),
                      subtitle: Text(
                        'R\$ ${p.precoVenda.toStringAsFixed(2)} • R\$ ${p.custo.toStringAsFixed(2)} • ${p.margem.toStringAsFixed(1)}%',
                      ),
                    ),
                  ListTile(
                    title: const Text('Categoria e marca'),
                    subtitle: Text(
                      '${p.categoria}${(p.marca ?? '').isEmpty ? '' : ' • ${p.marca}'}',
                    ),
                  ),
                  ListTile(
                    title: const Text('Código de barras'),
                    subtitle: Text(
                      (p.codigoBarras ?? '').isEmpty
                          ? 'Não informado'
                          : p.codigoBarras!,
                    ),
                  ),
                  if (SessionController.instance.usuario!.podeAcao(
                    AcaoPermissao.movimentarEstoque,
                  ))
                    FilledButton.icon(
                      onPressed: () => movimentar(p),
                      icon: const Icon(Icons.swap_vert),
                      label: const Text('Adicionar, retirar ou ajustar'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HistoricoProdutoPage(produto: p),
                      ),
                    ),
                    icon: const Icon(Icons.history),
                    label: const Text('Histórico completo'),
                  ),
                ],
              ),
      );
    },
  );
}

class HistoricoProdutoPage extends StatelessWidget {
  final ProdutoLoja produto;
  const HistoricoProdutoPage({super.key, required this.produto});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Histórico • ${produto.nome}')),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: LojaRepository().historico(produto.id),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.data!.isEmpty) {
          return const Center(child: Text('Sem movimentações.'));
        }
        return ListView(
          children: snap.data!
              .map(
                (m) => ListTile(
                  leading: Icon(
                    (m['quantidade_posterior'] as num) >=
                            (m['quantidade_anterior'] as num)
                        ? Icons.add_circle_outline
                        : Icons.remove_circle_outline,
                  ),
                  title: Text('${m['tipo']} • ${m['quantidade']}'),
                  subtitle: Text(
                    '${m['quantidade_anterior']} → ${m['quantidade_posterior']}\n${m['motivo'] ?? ''}',
                  ),
                  isThreeLine: true,
                ),
              )
              .toList(),
        );
      },
    ),
  );
}
