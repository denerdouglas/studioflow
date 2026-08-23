import 'package:flutter/material.dart';

import '../core/utils/id_generator.dart';
import '../models/domain/acesso.dart';
import '../models/domain/loja.dart';
import '../core/enums/tipo_produto.dart';
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
  final bool abrirScanner;

  const ProdutosLojaPage({
    super.key,
    this.somenteBaixo = false,
    this.modalidade,
    this.somenteUsoInterno = false,
    this.somenteAtivos = false,
    this.abrirScanner = false,
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
    if (widget.abrirScanner) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _lerCodigo());
    }
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
    final result = await Navigator.push<ScannerResult?>(
      context,
      MaterialPageRoute(builder: (_) => const VisionScannerPage()),
    );
    if (!mounted || result == null) return;

    if (result.tipo == ScannerResultType.cancelado) return;
    if (result.tipo == ScannerResultType.produtoExistente ||
        result.tipo == ScannerResultType.produtoNovo) {
      if (result.produto != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProdutoDetalhePage(produtoId: result.produto!.id),
          ),
        );
        setState(_carregar);
        return;
      }
    }

    final codigo =
        result.draft?.referenciaComercial?.value ?? result.draft?.gtin?.value;
    if (codigo == null) return;

    try {
      final produto = await _repo.buscarCodigo(codigo);
      if (!mounted) return;
      if (produto == null) {
        final resLookup = await _lookup.lookup(
          codigo,
          commerceId: SessionController.instance.usuario!.comercioId,
        );
        if (!mounted) return;
        final found = resLookup.product;
        if (found?.localProductId != null &&
            found?.localDestination == 'salao') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Produto jÃ¡ cadastrado no estoque do salÃ£o.'),
            ),
          );
          await Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => const EstoquePage()),
          );
        } else {
          await _abrir(null, resLookup.normalizedGtin, found, found == null);
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
                hintText: 'Nome, marca ou cÃ³digo',
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
                                  '${p.nome}${p.tipoProduto == 'uso_interno' ? ' (NÃƒO DESTINADO Ã€ VENDA)' : ''}${p.tipoProduto == 'ambos' ? ' (POSSUI SALDO COMERCIAL)' : ''}',
                                  style: TextStyle(
                                    color: p.tipoProduto == 'uso_interno'
                                        ? Colors.red
                                        : null,
                                    fontWeight: p.tipoProduto == 'uso_interno'
                                        ? FontWeight.bold
                                        : null,
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

  TipoProduto tipoProduto = TipoProduto.venda;
  bool ativo = true;
  bool salvando = false;
  bool consultandoCodigo = false;
  late String origemCatalogo;
  List<FornecedorLoja>? fornecedores;
  String? fornecedorSelecionado;

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
    ativo = p?.ativo ?? true;

    if (p != null) {
      tipoProduto = TipoProduto.values.firstWhere(
        (t) => t.toStorage() == p.tipoProduto,
        orElse: () => TipoProduto.venda,
      );
    }

    fornecedorSelecionado = p?.fornecedorPrincipalId;

    _c(
      'nome',
      p?.nome ?? catalog?.name ?? widget.draftInicial?.nome?.value ?? '',
    );
    _c(
      'marca',
      p?.marca ?? catalog?.brand ?? widget.draftInicial?.marca?.value ?? '',
    );
    _c(
      'categoria',
      p?.categoria ??
          catalog?.category ??
          widget.draftInicial?.categoriaSugerida?.value ??
          'CosmÃ©ticos',
    );

    // Campos mantidos por compatibilidade (ocultos ou com default)
    _c('interno', p?.codigoInterno ?? '');
    _c(
      'descricao',
      p?.descricao ??
          catalog?.description ??
          widget.draftInicial?.descricao?.value ??
          '',
    );
    _c('minimo', p?.estoqueMinimo.toString() ?? '0');
    _c('sugerida', p?.quantidadeSugerida.toString() ?? '0');
    _c('embalagem', p?.quantidadeEmbalagem.toString() ?? '1');
    _c('lote', p?.lote ?? '');
    _c('validade', p?.validade?.toIso8601String().split('T').first ?? '');
    _c('imagem', p?.imagem ?? catalog?.imageUrl ?? '');
    _c('observacoes', p?.observacoes ?? '');

    _c(
      'barras',
      p?.codigoBarras ??
          widget.codigoInicial ??
          catalog?.gtin ??
          widget.draftInicial?.gtin?.value ??
          '',
    );
    _c('custo', p?.custo.toStringAsFixed(2) ?? '0');
    _c('preco', p?.precoVenda.toStringAsFixed(2) ?? '0');
    _c('quantidade', p?.quantidadeAtual.toString() ?? '1');

    _c(
      'conteudo',
      p?.conteudoPorUnidade.toString() ??
          catalog?.contentPerUnit?.toString() ??
          '1',
    );
    _c('unidade_conteudo', p?.unidadeConteudo ?? catalog?.contentUnit ?? 'un');

    _c('quantidade').addListener(_updateTotal);
    _c('custo').addListener(_updateTotal);

    _carregarFornecedores();
  }

  Future<void> _carregarFornecedores() async {
    try {
      final f = await LojaRepository().listarFornecedores(ativos: true);
      if (mounted) setState(() => fornecedores = f);
    } catch (_) {}
  }

  void _updateTotal() {
    setState(() {});
  }

  double get _totalCompra => _n('quantidade') * _n('custo');

  Future<void> _scan() async {
    final result = await Navigator.push<ScannerResult?>(
      context,
      MaterialPageRoute(builder: (_) => const VisionScannerPage()),
    );
    if (!mounted || result == null) return;
    final codigo =
        result.draft?.referenciaComercial?.value ?? result.draft?.gtin?.value;
    if (codigo == null) return;
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
            content: Text('Produto jÃ¡ cadastrado no estoque do salÃ£o.'),
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
              _c('categoria').text == 'CosmÃ©ticos') {
            _c('categoria').text = product.category ?? 'CosmÃ©ticos';
          }
          if (_c('imagem').text.trim().isEmpty) {
            _c('imagem').text = product.imageUrl ?? '';
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
                'Produto nÃ£o encontrado. Complete os dados para cadastrÃ¡-lo.',
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
      final custo = _n('custo');
      final preco = tipoProduto == TipoProduto.usoInterno ? 0.0 : _n('preco');

      final produto = ProdutoLoja(
        id: widget.produto?.id ?? IdGenerator.temporal(),
        comercioId: SessionController.instance.usuario!.comercioId,
        nome: _c('nome').text,
        tipoProduto: tipoProduto.toStorage(),
        descricao: _c('descricao').text,
        categoria: _c('categoria').text,
        marca: _c('marca').text,
        codigoInterno: _c('interno').text,
        codigoBarras: _c('barras').text,
        tipo: tipoProduto == TipoProduto.usoInterno ? 'insumo' : 'produto',
        modalidade: widget.produto?.modalidade ?? ModalidadeProduto.proprio,
        fornecedorPrincipalId: fornecedorSelecionado,
        custo: custo,
        precoVenda: preco,
        margem: preco == 0 ? 0 : ((preco - custo) / preco) * 100,
        quantidadeAtual: widget.produto == null
            ? _n('quantidade')
            : widget.produto!.quantidadeAtual,
        estoqueMinimo: _n('minimo'),
        quantidadeSugerida: _n('sugerida'),
        unidade: _c('unidade_conteudo').text == 'un' ? 'un' : 'pote',
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
        ? (v) => (v ?? '').trim().isEmpty ? 'Campo obrigatÃ³rio' : null
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
  Widget build(BuildContext context) {
    return Scaffold(
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
                    'Produto nÃ£o encontrado. Complete os dados para cadastrÃ¡-lo.',
                  ),
                ),
              ),
            if (consultandoCodigo) const LinearProgressIndicator(),

            // P1 - ESCOLHA DO TIPO
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: SegmentedButton<TipoProduto>(
                segments: [
                  const ButtonSegment(
                    value: TipoProduto.venda,
                    label: Text('Venda'),
                    icon: Icon(Icons.storefront),
                  ),
                  const ButtonSegment(
                    value: TipoProduto.usoInterno,
                    label: Text('Uso no salÃ£o'),
                    icon: Icon(Icons.content_cut),
                  ),
                  if (tipoProduto == TipoProduto.ambos)
                    const ButtonSegment(
                      value: TipoProduto.ambos,
                      label: Text('Ambos'),
                      icon: Icon(Icons.all_inclusive),
                    ),
                ],
                selected: {tipoProduto},
                onSelectionChanged: (Set<TipoProduto> newSelection) {
                  setState(() {
                    tipoProduto = newSelection.first;
                  });
                },
              ),
            ),

            const SizedBox(height: 16),
            const Text(
              'DADOS DO PRODUTO',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),

            _campo('nome', 'Nome', obrigatorio: true),
            _campo('marca', 'Marca'),

            // P15 - FORNECEDOR
            if (fornecedores != null)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Fornecedor'),
                  initialValue: fornecedorSelecionado,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Nenhum')),
                    ...fornecedores!.map(
                      (f) => DropdownMenuItem(value: f.id, child: Text(f.nome)),
                    ),
                  ],
                  onChanged: (v) => setState(() => fornecedorSelecionado = v),
                ),
              ),

            _campo('categoria', 'Categoria'),
            _campo(
              'barras',
              'CÃ³digo / cÃ³digo de barras',
              suffix: IconButton(
                onPressed: consultandoCodigo ? null : _scan,
                icon: const Icon(Icons.barcode_reader),
              ),
            ),
            _campo('descricao', 'DescriÃ§Ã£o (opcional)', linhas: 2),

            const SizedBox(height: 24),
            const Text(
              'ESTOQUE E VALORES',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),

            if (widget.produto == null) ...[
              _campo(
                'quantidade',
                'Quantidade comprada',
                numero: true,
                obrigatorio: true,
              ),
            ],

            _campo(
              'custo',
              'Valor pago por unidade',
              numero: true,
              obrigatorio: true,
            ),

            if (tipoProduto != TipoProduto.usoInterno)
              _campo(
                'preco',
                'PreÃ§o de venda',
                numero: true,
                obrigatorio: true,
              ),

            if (widget.produto == null && _totalCompra > 0)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Text(
                  'Total da compra:\nR\$ ${_totalCompra.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

            const SizedBox(height: 24),
            const Text(
              'CONTEÃšDO',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),

            Row(
              children: [
                Expanded(child: _campo('conteudo', 'ConteÃºdo', numero: true)),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Unidade'),
                    initialValue: _c('unidade_conteudo').text.isEmpty
                        ? 'un'
                        : _c('unidade_conteudo').text,
                    items: const [
                      DropdownMenuItem(value: 'ml', child: Text('ml')),
                      DropdownMenuItem(value: 'L', child: Text('L')),
                      DropdownMenuItem(value: 'g', child: Text('g')),
                      DropdownMenuItem(value: 'kg', child: Text('kg')),
                      DropdownMenuItem(value: 'un', child: Text('un')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _c('unidade_conteudo').text = v);
                      }
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
            SwitchListTile(
              value: ativo,
              onChanged: (v) => setState(() => ativo = v),
              title: const Text('Produto ativo'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: salvando ? null : _salvar,
              icon: const Icon(Icons.save),
              label: Text(salvando ? 'Salvando...' : 'SALVAR PRODUTO'),
            ),
          ],
        ),
      ),
    );
  }
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
  List<FornecedorLoja>? fornecedores;

  @override
  void initState() {
    super.initState();
    future = repo.buscarProduto(widget.produtoId);
    _carregarFornecedores();
  }

  Future<void> _carregarFornecedores() async {
    try {
      final f = await repo.listarFornecedores();
      if (mounted) setState(() => fornecedores = f);
    } catch (_) {}
  }

  void recarregar() =>
      setState(() => future = repo.buscarProduto(widget.produtoId));

  Future<void> _excluirProduto(ProdutoLoja p) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir produto'),
        content: const Text('Tem certeza que deseja excluir este produto?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      // Inativa em vez de deletar fisicamente, para preservar histÃ³rico
      final pInativo = ProdutoLoja(
        id: p.id,
        comercioId: p.comercioId,
        nome: p.nome,
        tipoProduto: p.tipoProduto,
        descricao: p.descricao,
        categoria: p.categoria,
        marca: p.marca,
        codigoInterno: p.codigoInterno,
        codigoBarras: p.codigoBarras,
        tipo: p.tipo,
        modalidade: p.modalidade,
        fornecedorPrincipalId: p.fornecedorPrincipalId,
        custo: p.custo,
        precoVenda: p.precoVenda,
        margem: p.margem,
        quantidadeAtual: p.quantidadeAtual,
        estoqueMinimo: p.estoqueMinimo,
        quantidadeSugerida: p.quantidadeSugerida,
        unidade: p.unidade,
        conteudoPorUnidade: p.conteudoPorUnidade,
        unidadeConteudo: p.unidadeConteudo,
        revisaoModelagemEstoque: p.revisaoModelagemEstoque,
        quantidadeEmbalagem: p.quantidadeEmbalagem,
        lote: p.lote,
        dataEntrada: p.dataEntrada,
        validade: p.validade,
        imagem: p.imagem,
        observacoes: p.observacoes,
        origemCatalogo: p.origemCatalogo,
        ativo: false,
        criadoEm: p.criadoEm,
        atualizadoEm: DateTime.now(),
      );
      await repo.salvarProduto(pInativo);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao excluir: $e')));
      }
    }
  }

  Future<void> _abrirAjusteEstoque(ProdutoLoja p) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AjusteEstoquePage(produto: p)),
    );
    recarregar();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ProdutoLoja?>(
    future: future,
    builder: (context, snap) {
      final p = snap.data;
      if (p == null && snap.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (p == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Produto nÃ£o encontrado')),
          body: const Center(
            child: Text('Produto nÃ£o existe ou foi removido.'),
          ),
        );
      }

      final isVenda = p.tipoProduto != 'uso_interno';

      String nomeFornecedor = 'NÃ£o informado';
      if (fornecedores != null && p.fornecedorPrincipalId != null) {
        try {
          nomeFornecedor = fornecedores!
              .firstWhere((f) => f.id == p.fornecedorPrincipalId)
              .nome;
        } catch (_) {}
      }

      return Scaffold(
        appBar: AppBar(title: Text(p.nome)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'DADOS DO PRODUTO',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            ListTile(
              title: const Text('Nome'),
              subtitle: Text(p.nome),
              dense: true,
            ),
            ListTile(
              title: const Text('Marca'),
              subtitle: Text(
                (p.marca ?? '').isEmpty ? 'NÃ£o informada' : p.marca!,
              ),
              dense: true,
            ),
            ListTile(
              title: const Text('Fornecedor'),
              subtitle: Text(nomeFornecedor),
              dense: true,
            ),
            ListTile(
              title: const Text('Categoria'),
              subtitle: Text(p.categoria),
              dense: true,
            ),
            ListTile(
              title: const Text('CÃ³digo / CÃ³digo de barras'),
              subtitle: Text(
                (p.codigoBarras ?? '').isEmpty
                    ? 'NÃ£o informado'
                    : p.codigoBarras!,
              ),
              dense: true,
            ),
            if ((p.descricao ?? '').isNotEmpty)
              ListTile(
                title: const Text('DescriÃ§Ã£o'),
                subtitle: Text(p.descricao!),
                dense: true,
              ),

            const Divider(height: 32),
            Text(
              'ESTOQUE E VALORES',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 8),

            ListTile(
              title: const Text('Estoque atual'),
              subtitle: Text(
                '${p.quantidadeAtual.toStringAsFixed(2).replaceAll(RegExp(r"([.]*0+)(?!.*\d)"), "")} un',
              ),
              trailing: p.estoqueBaixo
                  ? const Icon(Icons.warning, color: Colors.orange)
                  : null,
              dense: true,
            ),

            if (SessionController.instance.usuario!.podeAcao(
              AcaoPermissao.visualizarCusto,
            ))
              ListTile(
                title: const Text('Custo (Valor pago por unidade)'),
                subtitle: Text('R\$ ${p.custo.toStringAsFixed(2)}'),
                dense: true,
              ),

            if (isVenda)
              ListTile(
                title: const Text('PreÃ§o de venda'),
                subtitle: Text('R\$ ${p.precoVenda.toStringAsFixed(2)}'),
                dense: true,
              ),

            const Divider(height: 32),
            Text(
              'CONTEÃšDO',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 8),

            ListTile(
              title: const Text('ConteÃºdo por unidade'),
              subtitle: Text(
                '${p.conteudoPorUnidade.toStringAsFixed(2).replaceAll(RegExp(r"([.]*0+)(?!.*\d)"), "")} ${p.unidadeConteudo}',
              ),
              dense: true,
            ),

            const SizedBox(height: 32),

            if (SessionController.instance.usuario!.podeAcao(
              AcaoPermissao.editarProduto,
            ))
              FilledButton.icon(
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
                label: const Text('EDITAR'),
              ),

            const SizedBox(height: 12),

            if (SessionController.instance.usuario!.podeAcao(
              AcaoPermissao.movimentarEstoque,
            ))
              OutlinedButton.icon(
                onPressed: () => _abrirAjusteEstoque(p),
                icon: const Icon(Icons.swap_vert),
                label: const Text('AJUSTAR ESTOQUE'),
              ),

            const SizedBox(height: 12),

            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HistoricoProdutoPage(produto: p),
                ),
              ),
              icon: const Icon(Icons.history),
              label: const Text('HISTÃ“RICO COMPLETO'),
            ),

            const SizedBox(height: 32),

            if (SessionController.instance.usuario!.podeAcao(
              AcaoPermissao.editarProduto,
            ))
              TextButton.icon(
                onPressed: () => _excluirProduto(p),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                icon: const Icon(Icons.delete_outline),
                label: const Text('EXCLUIR PRODUTO'),
              ),
          ],
        ),
      );
    },
  );
}

class AjusteEstoquePage extends StatefulWidget {
  final ProdutoLoja produto;
  const AjusteEstoquePage({super.key, required this.produto});

  @override
  State<AjusteEstoquePage> createState() => _AjusteEstoquePageState();
}

class _AjusteEstoquePageState extends State<AjusteEstoquePage> {
  String mode = 'entrada'; // 'entrada', 'saida', 'ajuste'
  final qtd = TextEditingController();
  final obs = TextEditingController();
  final repo = LojaRepository();
  bool salvando = false;

  @override
  void dispose() {
    qtd.dispose();
    obs.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final val = double.tryParse(qtd.text.replaceAll(',', '.')) ?? 0;
    if (val <= 0 && mode != 'ajuste') {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Quantidade invÃ¡lida.')));
      return;
    }
    if (mode == 'ajuste' && val < 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saldo invÃ¡lido.')));
      return;
    }
    if (mode == 'ajuste' && obs.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Motivo obrigatÃ³rio para ajuste de saldo.'),
        ),
      );
      return;
    }
    if (mode == 'saida' && obs.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Motivo obrigatÃ³rio para saÃ­da.')),
      );
      return;
    }

    setState(() => salvando = true);

    try {
      if (mode == 'ajuste') {
        final diff = val - widget.produto.quantidadeAtual;
        if (diff == 0) {
          Navigator.pop(context);
          return;
        }
        await repo.movimentar(
          produtoId: widget.produto.id,
          tipo: TipoMovimentoLoja.ajuste,
          quantidade: diff.abs(),
          origem: 'ajuste_saldo',
          observacao: 'Ajuste de saldo: ${obs.text}',
        );
      } else if (mode == 'entrada') {
        await repo.movimentar(
          produtoId: widget.produto.id,
          tipo: TipoMovimentoLoja.entradaManual,
          quantidade: val,
          origem: 'entrada_manual',
          observacao: obs.text.isNotEmpty ? obs.text : 'Entrada manual',
        );
      } else if (mode == 'saida') {
        await repo.movimentar(
          produtoId: widget.produto.id,
          tipo: TipoMovimentoLoja.saidaManual,
          quantidade: val,
          origem: 'saida_manual',
          observacao: obs.text,
        );
      }

      if (mounted) { Navigator.pop(context); }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) { setState(() => salvando = false); }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustar Estoque')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Estoque atual: ${widget.produto.quantidadeAtual.toStringAsFixed(2).replaceAll(RegExp(r"([.]*0+)(?!.*\d)"), "")}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          const Text('O que deseja fazer?'),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'entrada', label: Text('+ ENTRADA')),
              ButtonSegment(value: 'saida', label: Text('- SAÃDA')),
              ButtonSegment(value: 'ajuste', label: Text('AJUSTAR SALDO')),
            ],
            selected: {mode},
            onSelectionChanged: (s) => setState(() {
              mode = s.first;
              qtd.clear();
              obs.clear();
            }),
          ),
          const SizedBox(height: 24),

          if (mode == 'entrada') ...[
            const Text(
              'ENTRADA',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            TextField(
              controller: qtd,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Quantidade a adicionar',
              ),
            ),
            TextField(
              controller: obs,
              decoration: const InputDecoration(
                labelText: 'Motivo (opcional, ex: Compra nova, ReposiÃ§Ã£o)',
              ),
            ),
          ] else if (mode == 'saida') ...[
            const Text('SAÃDA', style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(
              controller: qtd,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Quantidade a remover',
              ),
            ),
            TextField(
              controller: obs,
              decoration: const InputDecoration(
                labelText: 'Motivo (uso no salÃ£o, perda, avaria, etc)',
              ),
            ),
          ] else if (mode == 'ajuste') ...[
            const Text(
              'AJUSTAR SALDO',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            TextField(
              controller: qtd,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Novo saldo exato'),
            ),
            TextField(
              controller: obs,
              decoration: const InputDecoration(
                labelText: 'Motivo obrigatÃ³rio (ex: Contagem fÃ­sica)',
              ),
            ),
          ],

          const SizedBox(height: 32),
          FilledButton(
            onPressed: salvando ? null : _salvar,
            child: Text(salvando ? 'Salvando...' : 'CONFIRMAR'),
          ),
        ],
      ),
    );
  }
}

class HistoricoProdutoPage extends StatelessWidget {
  final ProdutoLoja produto;
  const HistoricoProdutoPage({super.key, required this.produto});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('HistÃ³rico â€¢ ${produto.nome}')),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: LojaRepository().historico(produto.id),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.data!.isEmpty) {
          return const Center(child: Text('Sem movimentaÃ§Ãµes.'));
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
                  title: Text('${m['tipo']} â€¢ ${m['quantidade']}'),
                  subtitle: Text(
                    '${m['quantidade_anterior']} â†’ ${m['quantidade_posterior']}\n${m['motivo'] ?? ''}',
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
