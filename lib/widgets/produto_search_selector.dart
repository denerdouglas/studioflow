import 'package:flutter/material.dart';

import '../models/domain/loja.dart';
import '../repositories/loja_repository.dart';

class ProdutoSearchSelector extends StatefulWidget {
  final bool apenasComEstoque;
  final bool apenasPecaUnica;

  const ProdutoSearchSelector({
    super.key,
    this.apenasComEstoque = true,
    this.apenasPecaUnica = false,
  });

  @override
  State<ProdutoSearchSelector> createState() => _ProdutoSearchSelectorState();
}

class _ProdutoSearchSelectorState extends State<ProdutoSearchSelector> {
  final _repository = LojaRepository();
  final _searchController = TextEditingController();
  List<ProdutoLoja> _todosProdutos = [];
  List<ProdutoLoja> _produtosFiltrados = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregarProdutos();
  }

  Future<void> _carregarProdutos() async {
    try {
      final produtos = await _repository.listarItensParaVenda();
      if (!mounted) return;
      setState(() {
        _todosProdutos = produtos;
        _filtrar(_searchController.text);
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao carregar produtos.')),
      );
    }
  }

  void _filtrar(String query) {
    final lowerQuery = query.toLowerCase();
    setState(() {
      _produtosFiltrados = _todosProdutos.where((p) {
        if (widget.apenasComEstoque && p.quantidadeAtual <= 0) return false;
        if (widget.apenasPecaUnica && p.tipo != 'peca_unica') return false;

        if (lowerQuery.isEmpty) return true;

        final nomeMatch = p.nome.toLowerCase().contains(lowerQuery);
        final codigoMatch =
            p.codigoInterno?.toLowerCase().contains(lowerQuery) ?? false;
        final gtinMatch =
            p.codigoBarras?.toLowerCase().contains(lowerQuery) ?? false;

        return nomeMatch || codigoMatch || gtinMatch;
      }).toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onChanged: _filtrar,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Pesquisar produto',
                hintText: 'Nome, Código Interno ou EAN/GTIN',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _filtrar('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          if (_carregando)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: _produtosFiltrados.isEmpty
                  ? Center(
                      child: Text(
                        'Nenhum produto encontrado.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _produtosFiltrados.length,
                      itemBuilder: (context, index) {
                        final p = _produtosFiltrados[index];
                        final codeInfo = [
                          if (p.codigoInterno != null &&
                              p.codigoInterno!.isNotEmpty)
                            p.codigoInterno,
                          if (p.codigoBarras != null &&
                              p.codigoBarras!.isNotEmpty)
                            p.codigoBarras,
                        ].join(' | ');

                        return ListTile(
                          title: Text(
                            codeInfo.isNotEmpty
                                ? '$codeInfo - ${p.nome}'
                                : p.nome,
                          ),
                          subtitle: Text(
                            '${p.modalidade == ModalidadeProduto.consignado ? 'Consignado' : 'Próprio'} • ${p.quantidadeAtual} ${p.unidade} • R\$ ${p.precoVenda.toStringAsFixed(2)}',
                          ),
                          enabled: p.quantidadeAtual > 0,
                          onTap: () => Navigator.pop(context, p),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}
