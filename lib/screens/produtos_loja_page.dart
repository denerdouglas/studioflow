import 'package:flutter/material.dart';

import '../core/utils/id_generator.dart';
import '../models/domain/acesso.dart';
import '../models/domain/loja.dart';
import '../repositories/loja_repository.dart';
import '../services/session_controller.dart';
import 'barcode_scanner_page.dart';

class ProdutosLojaPage extends StatefulWidget {
  final bool somenteBaixo;
  final ModalidadeProduto? modalidade;
  const ProdutosLojaPage({
    super.key,
    this.somenteBaixo = false,
    this.modalidade,
  });

  @override
  State<ProdutosLojaPage> createState() => _ProdutosLojaPageState();
}

class _ProdutosLojaPageState extends State<ProdutosLojaPage> {
  final _repo = LojaRepository();
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
    incluirInativos: true,
  );

  Future<void> _abrir([ProdutoLoja? produto, String? codigo]) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            ProdutoFormPage(produto: produto, codigoInicial: codigo),
      ),
    );
    setState(_carregar);
  }

  Future<void> _lerCodigo() async {
    final codigo = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (!mounted || codigo == null) return;
    try {
      final produto = await _repo.buscarCodigo(codigo);
      if (!mounted) return;
      if (produto == null) {
        final cadastrar = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Produto não encontrado'),
            content: Text('Cadastrar um novo produto com o código $codigo?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Cadastrar'),
              ),
            ],
          ),
        );
        if (cadastrar == true) await _abrir(null, codigo);
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
                return RefreshIndicator(
                  onRefresh: () async => setState(_carregar),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: itens.length,
                    itemBuilder: (context, i) {
                      final p = itens[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        color: p.estoqueBaixo ? Colors.orange.shade50 : null,
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Icon(
                              p.modalidade == ModalidadeProduto.consignado
                                  ? Icons.handshake
                                  : Icons.shopping_bag,
                            ),
                          ),
                          title: Text(p.nome),
                          subtitle: Text(
                            '${p.categoria} • ${p.quantidadeAtual.toStringAsFixed(2)} ${p.unidade}\nR\$ ${p.precoVenda.toStringAsFixed(2)}${p.ativo ? '' : ' • Inativo'}',
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
  const ProdutoFormPage({super.key, this.produto, this.codigoInicial});
  @override
  State<ProdutoFormPage> createState() => _ProdutoFormPageState();
}

class _ProdutoFormPageState extends State<ProdutoFormPage> {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> c = {};
  ModalidadeProduto modalidade = ModalidadeProduto.proprio;
  bool ativo = true;
  bool salvando = false;

  TextEditingController _c(String key, [String value = '']) =>
      c.putIfAbsent(key, () => TextEditingController(text: value));
  double _n(String key) =>
      double.tryParse(_c(key).text.replaceAll(',', '.')) ?? 0;

  @override
  void initState() {
    super.initState();
    final p = widget.produto;
    modalidade = p?.modalidade ?? ModalidadeProduto.proprio;
    ativo = p?.ativo ?? true;
    _c('nome', p?.nome ?? '');
    _c('descricao', p?.descricao ?? '');
    _c('categoria', p?.categoria ?? 'Cosméticos');
    _c('marca', p?.marca ?? '');
    _c('interno', p?.codigoInterno ?? '');
    _c('barras', p?.codigoBarras ?? widget.codigoInicial ?? '');
    _c('tipo', p?.tipo ?? 'produto');
    _c('custo', p?.custo.toStringAsFixed(2) ?? '0');
    _c('preco', p?.precoVenda.toStringAsFixed(2) ?? '0');
    _c('quantidade', p?.quantidadeAtual.toString() ?? '0');
    _c('minimo', p?.estoqueMinimo.toString() ?? '0');
    _c('sugerida', p?.quantidadeSugerida.toString() ?? '0');
    _c('unidade', p?.unidade ?? 'un');
    _c('embalagem', p?.quantidadeEmbalagem.toString() ?? '1');
    _c('lote', p?.lote ?? '');
    _c('validade', p?.validade?.toIso8601String().split('T').first ?? '');
    _c('imagem', p?.imagem ?? '');
    _c('observacoes', p?.observacoes ?? '');
  }

  Future<void> _scan() async {
    final codigo = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (codigo != null) setState(() => _c('barras').text = codigo);
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
        quantidadeEmbalagem: _n('embalagem'),
        lote: _c('lote').text,
        dataEntrada: widget.produto?.dataEntrada ?? agora,
        validade: DateTime.tryParse(_c('validade').text),
        imagem: _c('imagem').text,
        observacoes: _c('observacoes').text,
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
          _campo('nome', 'Nome', obrigatorio: true),
          _campo('descricao', 'Descrição', linhas: 2),
          _campo('categoria', 'Categoria', obrigatorio: true),
          _campo('marca', 'Marca'),
          _campo('interno', 'Código interno'),
          _campo(
            'barras',
            'Código de barras',
            suffix: IconButton(
              onPressed: _scan,
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
              Expanded(child: _campo('unidade', 'Unidade', obrigatorio: true)),
              const SizedBox(width: 12),
              Expanded(
                child: _campo('embalagem', 'Qtd. por embalagem', numero: true),
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
