import 'package:flutter/material.dart';

import '../core/routes/app_routes.dart';

import '../repositories/estoque_repository.dart';
import '../repositories/inventory_transfer_repository.dart';
import 'barcode_scanner_page.dart';

class EstoquePage extends StatefulWidget {
  const EstoquePage({super.key});

  @override
  State<EstoquePage> createState() => _EstoquePageState();
}

class _EstoquePageState extends State<EstoquePage> {
  static const Color _roxo = Color(0xFF70569A);
  static const Color _fundo = Color(0xFFF9F6FC);
  static const Color _texto = Color(0xFF2D2140);
  static const Color _textoClaro = Color(0xFF766A85);
  static const Color _verde = Color(0xFF15996B);
  static const Color _laranja = Color(0xFFE58A25);
  static const Color _vermelho = Color(0xFFD64D64);

  final EstoqueRepository _repository = EstoqueRepository();
  final InventoryTransferRepository _transferRepository =
      InventoryTransferRepository();
  final TextEditingController _pesquisaController = TextEditingController();

  List<ItemEstoqueRegistro> _itens = [];
  ResumoEstoque _resumo = ResumoEstoque.vazio();

  bool _carregando = true;
  bool _mostrarInativos = true;
  String _pesquisa = '';
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  @override
  void dispose() {
    _pesquisaController.dispose();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    try {
      final resultados = await Future.wait([
        _repository.listar(incluirInativos: _mostrarInativos),
        _repository.resumo(),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _itens = resultados[0] as List<ItemEstoqueRegistro>;
        _resumo = resultados[1] as ResumoEstoque;
        _carregando = false;
        _erro = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
        _erro = 'Não foi possível carregar o estoque.';
      });
    }
  }

  List<ItemEstoqueRegistro> get _itensFiltrados {
    final texto = _pesquisa.trim().toLowerCase();

    if (texto.isEmpty) {
      return _itens;
    }

    return _itens.where((item) {
      return item.nome.toLowerCase().contains(texto) ||
          item.categoria.toLowerCase().contains(texto) ||
          item.fornecedor.toLowerCase().contains(texto) ||
          item.codigoBarras.toLowerCase().contains(texto);
    }).toList();
  }

  Future<void> _lerParaPesquisa() async {
    final codigo = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (!mounted || codigo == null) return;
    _pesquisaController.text = codigo;
    setState(() => _pesquisa = codigo);
  }

  Future<void> _novoItem() async {
    final item = await showModalBottomSheet<ItemEstoqueRegistro>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ItemEstoqueFormSheet(),
    );

    if (item == null) {
      return;
    }

    try {
      final existe = await _repository.existeNome(nome: item.nome);

      if (existe) {
        throw StateError('Já existe um item com esse nome.');
      }

      await _repository.inserir(item);
      await _atualizarAposAcao('Item cadastrado com sucesso.');
    } catch (erro) {
      _mostrarErro(
        erro is StateError
            ? erro.message
            : 'Não foi possível cadastrar o item.',
      );
    }
  }

  Future<void> _editarItem(ItemEstoqueRegistro item) async {
    final atualizado = await showModalBottomSheet<ItemEstoqueRegistro>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ItemEstoqueFormSheet(itemInicial: item),
    );

    if (atualizado == null) {
      return;
    }

    try {
      final existe = await _repository.existeNome(
        nome: atualizado.nome,
        ignorarId: atualizado.id,
      );

      if (existe) {
        throw StateError('Já existe outro item com esse nome.');
      }

      await _repository.atualizar(atualizado);

      await _atualizarAposAcao('Item atualizado com sucesso.');
    } catch (erro) {
      _mostrarErro(
        erro is StateError
            ? erro.message
            : 'Não foi possível atualizar o item.',
      );
    }
  }

  Future<void> _movimentarItem(ItemEstoqueRegistro item) async {
    final resultado =
        await showModalBottomSheet<MovimentacaoEstoqueFormularioResultado>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => MovimentacaoEstoqueSheet(item: item),
        );

    if (resultado == null) {
      return;
    }

    try {
      switch (resultado.tipo) {
        case 'entrada':
          await _repository.registrarEntrada(
            itemId: item.id,
            quantidade: resultado.quantidade,
            motivo: resultado.motivo,
          );
          break;

        case 'saida':
          await _repository.registrarSaida(
            itemId: item.id,
            quantidade: resultado.quantidade,
            motivo: resultado.motivo,
          );
          break;

        case 'ajuste':
          await _repository.ajustarQuantidade(
            itemId: item.id,
            novaQuantidade: resultado.quantidade,
            motivo: resultado.motivo,
          );
          break;
      }

      await _atualizarAposAcao('Movimentação registrada.');
    } catch (erro) {
      _mostrarErro(
        erro is StateError
            ? erro.message
            : 'Não foi possível registrar a movimentação.',
      );
    }
  }

  Future<void> _alterarStatus(ItemEstoqueRegistro item) async {
    try {
      await _repository.alterarStatus(id: item.id, ativo: !item.ativo);

      await _atualizarAposAcao(
        item.ativo ? 'Item desativado.' : 'Item reativado.',
      );
    } catch (_) {
      _mostrarErro('Não foi possível alterar o item.');
    }
  }

  Future<void> _abrirHistorico(ItemEstoqueRegistro item) async {
    await Navigator.push(
      context,
      AppRoutes.material(
        builder: (_) =>
            HistoricoEstoquePage(item: item, repository: _repository),
      ),
    );
  }

  Future<void> _abrirOpcoes(ItemEstoqueRegistro item) async {
    final acao = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => OpcoesItemEstoqueSheet(item: item),
    );

    switch (acao) {
      case 'movimentar':
        await _movimentarItem(item);
        break;

      case 'transferir':
        await _transferirParaLoja(item);
        break;

      case 'editar':
        await _editarItem(item);
        break;

      case 'historico':
        await _abrirHistorico(item);
        break;

      case 'status':
        await _alterarStatus(item);
        break;
    }
  }

  Future<void> _transferirParaLoja(ItemEstoqueRegistro item) async {
    final quantity = TextEditingController();
    final reason = TextEditingController(text: 'Reposição da Loja do Salão');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transferir para a loja'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Disponível no salão: ${item.quantidadeAtual} ${item.unidade}',
            ),
            TextField(
              controller: quantity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Quantidade'),
            ),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'Motivo'),
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
            child: const Text('Confirmar transferência'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _transferRepository.transferToStore(
        sourceProductId: item.id,
        quantity: double.tryParse(quantity.text.replaceAll(',', '.')) ?? 0,
        reason: reason.text,
      );
      await _atualizarAposAcao(
        'Transferência registrada. Confira o preço antes de vender na loja.',
      );
    } catch (error) {
      _mostrarErro(error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      quantity.dispose();
      reason.dispose();
    }
  }

  Future<void> _atualizarAposAcao(String mensagem) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _carregando = true;
    });

    await _carregarDados();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), behavior: SnackBarBehavior.floating),
    );
  }

  void _mostrarErro(String mensagem) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), behavior: SnackBarBehavior.floating),
    );
  }

  String _formatarDinheiro(double valor) {
    return 'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundo,
      appBar: AppBar(
        backgroundColor: _fundo,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Estoque',
          style: TextStyle(fontWeight: FontWeight.bold, color: _texto),
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: () {
              setState(() {
                _carregando = true;
              });

              _carregarDados();
            },
            icon: const Icon(Icons.refresh, color: _roxo),
          ),
        ],
      ),
      body: Column(
        children: [
          _construirResumo(),
          const SizedBox(height: 12),
          _construirPesquisa(),
          const SizedBox(height: 8),
          Expanded(child: _construirConteudo()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
      heroTag: null,
      onPressed: _novoItem,
        backgroundColor: _roxo,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text(
          'Novo item',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _construirResumo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF70569A), Color(0xFF9A78C5)],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Valor em estoque',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 7),
                Text(
                  _formatarDinheiro(_resumo.valorTotal),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 31,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ResumoCard(
                  titulo: 'Ativos',
                  valor: '${_resumo.itensAtivos}',
                  icone: Icons.inventory_2_outlined,
                  cor: _verde,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _ResumoCard(
                  titulo: 'Baixo',
                  valor: '${_resumo.itensEstoqueBaixo}',
                  icone: Icons.warning_amber_rounded,
                  cor: _laranja,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _ResumoCard(
                  titulo: 'Vencidos',
                  valor: '${_resumo.itensVencidos}',
                  icone: Icons.event_busy_outlined,
                  cor: _vermelho,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _construirPesquisa() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        children: [
          TextField(
            controller: _pesquisaController,
            decoration: InputDecoration(
              hintText: 'Pesquisar item, categoria ou fornecedor...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _pesquisa.isEmpty
                  ? IconButton(
                      tooltip: 'Ler código',
                      onPressed: _lerParaPesquisa,
                      icon: const Icon(Icons.barcode_reader),
                    )
                  : IconButton(
                      onPressed: () {
                        _pesquisaController.clear();

                        setState(() {
                          _pesquisa = '';
                        });
                      },
                      icon: const Icon(Icons.close),
                    ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (texto) {
              setState(() {
                _pesquisa = texto;
              });
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Switch(
                value: _mostrarInativos,
                activeThumbColor: _roxo,
                onChanged: (valor) async {
                  setState(() {
                    _mostrarInativos = valor;
                    _carregando = true;
                  });

                  await _carregarDados();
                },
              ),
              const Text(
                'Mostrar inativos',
                style: TextStyle(
                  color: _textoClaro,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _construirConteudo() {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _erro!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _textoClaro, fontSize: 16),
          ),
        ),
      );
    }

    final itens = _itensFiltrados;

    if (itens.isEmpty) {
      return const Center(
        child: Text(
          'Nenhum item encontrado.',
          style: TextStyle(fontSize: 16, color: _textoClaro),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 100),
      itemCount: itens.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = itens[index];

        final estoqueBaixo = item.quantidadeAtual <= item.estoqueMinimo;

        final vencido =
            item.dataValidade != null &&
            item.dataValidade!.isBefore(DateTime.now());

        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _abrirOpcoes(item),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: estoqueBaixo
                    ? _laranja
                    : vencido
                    ? _vermelho
                    : const Color(0xFFE8E1F0),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: item.ativo
                      ? _roxo.withValues(alpha: .12)
                      : Colors.grey.withValues(alpha: .15),
                  child: Icon(
                    Icons.inventory_2,
                    color: item.ativo ? _roxo : Colors.grey,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.nome,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: _texto,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.categoria,
                        style: const TextStyle(color: _textoClaro),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${item.quantidadeAtual.toStringAsFixed(2)} ${item.unidade}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatarDinheiro(item.custoUnitario),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Icon(Icons.chevron_right, color: _roxo),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ResumoCard extends StatelessWidget {
  final String titulo;
  final String valor;
  final IconData icone;
  final Color cor;

  const _ResumoCard({
    required this.titulo,
    required this.valor,
    required this.icone,
    required this.cor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(icone, color: cor),
          const SizedBox(height: 8),
          Text(
            valor,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 3),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF766A85), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class OpcoesItemEstoqueSheet extends StatelessWidget {
  final ItemEstoqueRegistro item;

  const OpcoesItemEstoqueSheet({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
      decoration: const BoxDecoration(
        color: Color(0xFFF9F6FC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFD6CDDD),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            item.nome,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D2140),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${item.quantidadeAtual.toStringAsFixed(2)} '
            '${item.unidade} disponíveis',
            style: const TextStyle(color: Color(0xFF766A85)),
          ),
          const SizedBox(height: 20),
          _OpcaoEstoque(
            titulo: 'Registrar movimentação',
            icone: Icons.swap_vert_rounded,
            cor: const Color(0xFF15996B),
            onTap: () {
              Navigator.pop(context, 'movimentar');
            },
          ),
          _OpcaoEstoque(
            titulo: 'Transferir para a Loja do Salão',
            icone: Icons.swap_horiz,
            cor: const Color(0xFFE58A25),
            onTap: () {
              Navigator.pop(context, 'transferir');
            },
          ),
          _OpcaoEstoque(
            titulo: 'Editar item',
            icone: Icons.edit_outlined,
            cor: const Color(0xFF70569A),
            onTap: () {
              Navigator.pop(context, 'editar');
            },
          ),
          _OpcaoEstoque(
            titulo: 'Ver histórico',
            icone: Icons.history,
            cor: const Color(0xFF3078C5),
            onTap: () {
              Navigator.pop(context, 'historico');
            },
          ),
          _OpcaoEstoque(
            titulo: item.ativo ? 'Desativar item' : 'Reativar item',
            icone: item.ativo
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            cor: item.ativo ? const Color(0xFFD64D64) : const Color(0xFF15996B),
            onTap: () {
              Navigator.pop(context, 'status');
            },
          ),
        ],
      ),
    );
  }
}

class _OpcaoEstoque extends StatelessWidget {
  final String titulo;
  final IconData icone;
  final Color cor;
  final VoidCallback onTap;

  const _OpcaoEstoque({
    required this.titulo,
    required this.icone,
    required this.cor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icone, color: cor),
      ),
      title: Text(
        titulo,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: Color(0xFF2D2140),
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class MovimentacaoEstoqueFormularioResultado {
  final String tipo;
  final double quantidade;
  final String motivo;

  const MovimentacaoEstoqueFormularioResultado({
    required this.tipo,
    required this.quantidade,
    required this.motivo,
  });
}

class MovimentacaoEstoqueSheet extends StatefulWidget {
  final ItemEstoqueRegistro item;

  const MovimentacaoEstoqueSheet({super.key, required this.item});

  @override
  State<MovimentacaoEstoqueSheet> createState() =>
      _MovimentacaoEstoqueSheetState();
}

class _MovimentacaoEstoqueSheetState extends State<MovimentacaoEstoqueSheet> {
  static const Color _roxo = Color(0xFF70569A);

  final TextEditingController _quantidadeController = TextEditingController();

  final TextEditingController _motivoController = TextEditingController();

  String _tipo = 'entrada';

  @override
  void dispose() {
    _quantidadeController.dispose();
    _motivoController.dispose();
    super.dispose();
  }

  void _salvar() {
    final quantidade = double.tryParse(
      _quantidadeController.text.trim().replaceAll(',', '.'),
    );

    final motivo = _motivoController.text.trim();

    if (quantidade == null || quantidade < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe uma quantidade válida.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      return;
    }

    if (_tipo != 'ajuste' && quantidade == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A quantidade deve ser maior que zero.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      return;
    }

    if (motivo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe o motivo da movimentação.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      return;
    }

    Navigator.pop(
      context,
      MovimentacaoEstoqueFormularioResultado(
        tipo: _tipo,
        quantidade: quantidade,
        motivo: motivo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(22, 22, 22, teclado + 25),
      decoration: const BoxDecoration(
        color: Color(0xFFF9F6FC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6CDDD),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Movimentar estoque',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D2140),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              widget.item.nome,
              style: const TextStyle(color: Color(0xFF766A85)),
            ),
            const SizedBox(height: 5),
            Text(
              'Atual: '
              '${widget.item.quantidadeAtual.toStringAsFixed(2)} '
              '${widget.item.unidade}',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF2D2140),
              ),
            ),
            const SizedBox(height: 20),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'entrada',
                  label: Text('Entrada'),
                  icon: Icon(Icons.add_circle_outline),
                ),
                ButtonSegment<String>(
                  value: 'saida',
                  label: Text('Saída'),
                  icon: Icon(Icons.remove_circle_outline),
                ),
                ButtonSegment<String>(
                  value: 'ajuste',
                  label: Text('Ajuste'),
                  icon: Icon(Icons.tune),
                ),
              ],
              selected: {_tipo},
              onSelectionChanged: (selecionados) {
                setState(() {
                  _tipo = selecionados.first;
                });
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _quantidadeController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: _tipo == 'ajuste'
                    ? 'Nova quantidade total'
                    : 'Quantidade',
                suffixText: widget.item.unidade,
                prefixIcon: const Icon(Icons.numbers),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _motivoController,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Motivo',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _salvar,
              icon: const Icon(Icons.save_outlined),
              label: const Text(
                'Registrar movimentação',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _roxo,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(57),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ItemEstoqueFormSheet extends StatefulWidget {
  final ItemEstoqueRegistro? itemInicial;

  const ItemEstoqueFormSheet({super.key, this.itemInicial});

  @override
  State<ItemEstoqueFormSheet> createState() => _ItemEstoqueFormSheetState();
}

class _ItemEstoqueFormSheetState extends State<ItemEstoqueFormSheet> {
  static const Color _roxo = Color(0xFF70569A);

  final TextEditingController _nomeController = TextEditingController();

  final TextEditingController _quantidadeController = TextEditingController();
  final TextEditingController _conteudoController = TextEditingController();

  final TextEditingController _estoqueMinimoController =
      TextEditingController();

  final TextEditingController _custoController = TextEditingController();

  final TextEditingController _fornecedorController = TextEditingController();

  final TextEditingController _codigoBarrasController = TextEditingController();

  final TextEditingController _observacoesController = TextEditingController();

  String _categoria = 'Materiais';
  String _tipo = 'consumivel';
  String _unidade = 'unidade';
  String _unidadeConteudo = 'g';

  bool _revisaoModelagemEstoque = false;

  bool _ativo = true;
  bool _descontarAutomaticamente = true;

  DateTime? _dataValidade;

  final List<String> _categorias = const [
    'Materiais',
    'Esmaltes',
    'Descartáveis',
    'Higiene',
    'Equipamentos',
    'Produtos',
    'Manutenção',
    'Outros',
  ];

  final List<String> _tipos = const ['consumivel', 'produto', 'equipamento'];

  final List<String> _unidades = const [
    'unidade',
    'caixa',
    'pacote',
    'frasco',
    'litro',
    'ml',
    'kg',
    'grama',
    'metro',
    'par',
  ];

  final List<String> _unidadesConteudo = const [
    'g',
    'kg',
    'ml',
    'litro',
    'cápsulas',
    'cm',
    'm',
    'unidade',
  ];

  @override
  void initState() {
    super.initState();

    final item = widget.itemInicial;

    if (item == null) {
      return;
    }

    _nomeController.text = item.nome;

    _quantidadeController.text = item.quantidadeAtual.toStringAsFixed(2);

    _estoqueMinimoController.text = item.estoqueMinimo.toStringAsFixed(2);

    _custoController.text = item.custoUnitario.toStringAsFixed(2);

    _fornecedorController.text = item.fornecedor;

    _codigoBarrasController.text = item.codigoBarras;

    _observacoesController.text = item.observacoes;

    _categoria = item.categoria;
    _tipo = item.tipo;
    _unidade = item.unidade;
    _conteudoController.text = item.conteudoPorUnidade.toStringAsFixed(2);
    _unidadeConteudo = item.unidadeConteudo;
    _revisaoModelagemEstoque = item.revisaoModelagemEstoque;
    _ativo = item.ativo;

    _descontarAutomaticamente = item.descontarAutomaticamente;

    _dataValidade = item.dataValidade;

    if (!_categorias.contains(_categoria)) {
      _categoria = 'Outros';
    }

    if (!_tipos.contains(_tipo)) {
      _tipo = 'consumivel';
    }

    if (!_unidades.contains(_unidade)) {
      _unidade = 'unidade';
    }

    if (!_unidadesConteudo.contains(_unidadeConteudo)) {
      _unidadeConteudo = 'g';
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _quantidadeController.dispose();
    _conteudoController.dispose();
    _estoqueMinimoController.dispose();
    _custoController.dispose();
    _fornecedorController.dispose();
    _codigoBarrasController.dispose();
    _observacoesController.dispose();

    super.dispose();
  }

  Future<void> _lerCodigo() async {
    final codigo = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (!mounted || codigo == null) return;
    setState(() => _codigoBarrasController.text = codigo);
  }

  Future<void> _selecionarValidade() async {
    final hoje = DateTime.now();

    final data = await showDatePicker(
      context: context,
      initialDate: _dataValidade ?? hoje,
      firstDate: DateTime(hoje.year - 5),
      lastDate: DateTime(hoje.year + 20),
      locale: const Locale('pt', 'BR'),
    );

    if (data == null) {
      return;
    }

    setState(() {
      _dataValidade = data;
    });
  }

  void _removerValidade() {
    setState(() {
      _dataValidade = null;
    });
  }

  void _salvar() {
    final nome = _nomeController.text.trim();

    final quantidade =
        double.tryParse(
          _quantidadeController.text.trim().replaceAll(',', '.'),
        ) ??
        0;

    final conteudo =
        double.tryParse(
          _conteudoController.text.trim().replaceAll(',', '.'),
        ) ??
        1;

    final estoqueMinimo =
        double.tryParse(
          _estoqueMinimoController.text.trim().replaceAll(',', '.'),
        ) ??
        0;

    final custo =
        double.tryParse(_custoController.text.trim().replaceAll(',', '.')) ?? 0;

    if (nome.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe o nome do item.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      return;
    }

    if (quantidade < 0 || estoqueMinimo < 0 || custo < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Quantidade, estoque mínimo e custo não podem ser negativos.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );

      return;
    }

    final agora = DateTime.now();
    final existente = widget.itemInicial;

    final item = ItemEstoqueRegistro(
      id: existente?.id ?? agora.microsecondsSinceEpoch.toString(),
      nome: nome,
      categoria: _categoria,
      tipo: _tipo,
      quantidadeAtual: quantidade,
      estoqueMinimo: estoqueMinimo,
      unidade: _unidade,
      conteudoPorUnidade: conteudo,
      unidadeConteudo: _unidadeConteudo,
      revisaoModelagemEstoque: false,
      custoUnitario: custo,
      fornecedor: _fornecedorController.text.trim(),
      codigoBarras: _codigoBarrasController.text.trim(),
      dataValidade: _dataValidade,
      ativo: _ativo,
      descontarAutomaticamente: _descontarAutomaticamente,
      observacoes: _observacoesController.text.trim(),
      dataCadastro: existente?.dataCadastro ?? agora,
    );

    Navigator.pop(context, item);
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;

    final editando = widget.itemInicial != null;

    return Container(
      padding: EdgeInsets.fromLTRB(22, 22, 22, teclado + 25),
      decoration: const BoxDecoration(
        color: Color(0xFFF9F6FC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6CDDD),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              editando ? 'Editar item' : 'Novo item',
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D2140),
              ),
            ),
            if (_revisaoModelagemEstoque) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3CD),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFEeba)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Color(0xFF856404)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Revisão necessária: Separe a quantidade física (potes, frascos) do conteúdo (g, ml). O cálculo financeiro usará apenas a quantidade física.',
                        style: TextStyle(color: Color(0xFF856404), fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            TextField(
              controller: _nomeController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nome do item',
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _categoria,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Categoria',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: _categorias.map((categoria) {
                return DropdownMenuItem(
                  value: categoria,
                  child: Text(categoria),
                );
              }).toList(),
              onChanged: (valor) {
                if (valor == null) {
                  return;
                }

                setState(() {
                  _categoria = valor;
                });
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _tipo,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Tipo de item',
                prefixIcon: Icon(Icons.tune),
              ),
              items: _tipos.map((tipo) {
                return DropdownMenuItem(value: tipo, child: Text(tipo));
              }).toList(),
              onChanged: (valor) {
                if (valor == null) {
                  return;
                }

                setState(() {
                  _tipo = valor;
                });
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantidadeController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Quantidade atual',
                      prefixIcon: Icon(Icons.numbers),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _unidade,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Unidade física (pote, caixa)'),
                    items: _unidades.map((unidade) {
                      return DropdownMenuItem(
                        value: unidade,
                        child: Text(unidade, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (valor) {
                      if (valor == null) {
                        return;
                      }

                      setState(() {
                        _unidade = valor;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _conteudoController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Conteúdo',
                      prefixIcon: Icon(Icons.scale_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _unidadeConteudo,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Unidade (g, ml)'),
                    items: _unidadesConteudo.map((unidade) {
                      return DropdownMenuItem(
                        value: unidade,
                        child: Text(unidade, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (valor) {
                      if (valor == null) return;
                      setState(() {
                        _unidadeConteudo = valor;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _estoqueMinimoController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Estoque mínimo',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _custoController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Custo unitário',
                      prefixText: 'R\$ ',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _fornecedorController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Fornecedor',
                prefixIcon: Icon(Icons.local_shipping_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _codigoBarrasController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Código de barras',
                prefixIcon: const Icon(Icons.qr_code),
                suffixIcon: IconButton(
                  tooltip: 'Ler com a câmera',
                  onPressed: _lerCodigo,
                  icon: const Icon(Icons.barcode_reader),
                ),
              ),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: _selecionarValidade,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Data de validade',
                  prefixIcon: const Icon(Icons.calendar_month_outlined),
                  suffixIcon: _dataValidade == null
                      ? null
                      : IconButton(
                          onPressed: _removerValidade,
                          icon: const Icon(Icons.close),
                        ),
                ),
                child: Text(
                  _dataValidade == null
                      ? 'Sem validade'
                      : _formatarData(_dataValidade!),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _observacoesController,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Observações',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _ativo,
              title: const Text('Item ativo'),
              activeThumbColor: _roxo,
              onChanged: (valor) {
                setState(() {
                  _ativo = valor;
                });
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _descontarAutomaticamente,
              title: const Text('Desconto automático'),
              activeThumbColor: _roxo,
              onChanged: (valor) {
                setState(() {
                  _descontarAutomaticamente = valor;
                });
              },
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _salvar,
              icon: const Icon(Icons.save_outlined),
              label: Text(
                editando ? 'Salvar alterações' : 'Salvar item',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _roxo,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(57),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatarData(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');

    final mes = data.month.toString().padLeft(2, '0');

    return '$dia/$mes/${data.year}';
  }
}

class HistoricoEstoquePage extends StatefulWidget {
  final ItemEstoqueRegistro item;
  final EstoqueRepository repository;

  const HistoricoEstoquePage({
    super.key,
    required this.item,
    required this.repository,
  });

  @override
  State<HistoricoEstoquePage> createState() => _HistoricoEstoquePageState();
}

class _HistoricoEstoquePageState extends State<HistoricoEstoquePage> {
  static const Color _roxo = Color(0xFF70569A);

  static const Color _fundo = Color(0xFFF9F6FC);

  static const Color _texto = Color(0xFF2D2140);

  static const Color _textoClaro = Color(0xFF766A85);

  List<MovimentacaoEstoqueRegistro> _movimentacoes = [];

  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregarHistorico();
  }

  Future<void> _carregarHistorico() async {
    try {
      final movimentacoes = await widget.repository.listarMovimentacoes(
        itemId: widget.item.id,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _movimentacoes = movimentacoes;
        _carregando = false;
        _erro = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
        _erro = 'Não foi possível carregar o histórico.';
      });
    }
  }

  String _formatarDataHora(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');

    final mes = data.month.toString().padLeft(2, '0');

    final hora = data.hour.toString().padLeft(2, '0');

    final minuto = data.minute.toString().padLeft(2, '0');

    return '$dia/$mes/${data.year} • $hora:$minuto';
  }

  String _tituloTipo(String tipo) {
    switch (tipo) {
      case 'entrada':
        return 'Entrada';
      case 'saida':
        return 'Saída';
      case 'ajuste':
        return 'Ajuste';
      default:
        return 'Movimentação';
    }
  }

  Color _corTipo(String tipo) {
    switch (tipo) {
      case 'entrada':
        return const Color(0xFF15996B);
      case 'saida':
        return const Color(0xFFD64D64);
      case 'ajuste':
        return const Color(0xFFE58A25);
      default:
        return _roxo;
    }
  }

  IconData _iconeTipo(String tipo) {
    switch (tipo) {
      case 'entrada':
        return Icons.add_circle_outline;
      case 'saida':
        return Icons.remove_circle_outline;
      case 'ajuste':
        return Icons.tune;
      default:
        return Icons.swap_vert;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundo,
      appBar: AppBar(
        backgroundColor: _fundo,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Histórico do estoque',
          style: TextStyle(fontWeight: FontWeight.bold, color: _texto),
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: () {
              setState(() {
                _carregando = true;
              });

              _carregarHistorico();
            },
            icon: const Icon(Icons.refresh, color: _roxo),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(18, 10, 18, 14),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE8E1F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.item.nome,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _texto,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Quantidade atual: '
                  '${widget.item.quantidadeAtual.toStringAsFixed(2)} '
                  '${widget.item.unidade}',
                  style: const TextStyle(color: _textoClaro),
                ),
              ],
            ),
          ),
          Expanded(child: _construirConteudo()),
        ],
      ),
    );
  }

  Widget _construirConteudo() {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator(color: _roxo));
    }

    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _erro!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _textoClaro, fontSize: 16),
          ),
        ),
      );
    }

    if (_movimentacoes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.history, size: 70, color: Color(0xFFB6A9C3)),
              SizedBox(height: 16),
              Text(
                'Nenhuma movimentação registrada',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _texto,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: _roxo,
      onRefresh: _carregarHistorico,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 30),
        itemCount: _movimentacoes.length,
        separatorBuilder: (_, _) {
          return const SizedBox(height: 10);
        },
        itemBuilder: (context, index) {
          final movimentacao = _movimentacoes[index];

          final cor = _corTipo(movimentacao.tipo);

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE8E1F0)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: cor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(_iconeTipo(movimentacao.tipo), color: cor),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _tituloTipo(movimentacao.tipo),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: cor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        movimentacao.motivo.isEmpty
                            ? 'Sem motivo informado'
                            : movimentacao.motivo,
                        style: const TextStyle(color: _texto),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatarDataHora(movimentacao.data),
                        style: const TextStyle(
                          fontSize: 12,
                          color: _textoClaro,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${movimentacao.quantidadeAnterior.toStringAsFixed(2)} '
                        '→ '
                        '${movimentacao.quantidadePosterior.toStringAsFixed(2)} '
                        '${widget.item.unidade}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _texto,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  movimentacao.tipo == 'entrada'
                      ? '+${movimentacao.quantidade.toStringAsFixed(2)}'
                      : movimentacao.tipo == 'saida'
                      ? '-${movimentacao.quantidade.toStringAsFixed(2)}'
                      : movimentacao.quantidade.toStringAsFixed(2),
                  style: TextStyle(fontWeight: FontWeight.bold, color: cor),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
