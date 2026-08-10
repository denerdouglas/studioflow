import 'package:flutter/material.dart';

import '../../models/domain/pacote_servico.dart';
import '../../repositories/pacotes_repository.dart';

class NovoPacotePage extends StatefulWidget {
  const NovoPacotePage({super.key});

  @override
  State<NovoPacotePage> createState() => _NovoPacotePageState();
}

class _NovoPacotePageState extends State<NovoPacotePage> {
  final _repository = PacotesRepository();
  bool _carregando = true;
  List<Map<String, Object?>> _servicos = [];

  final _nome = TextEditingController();
  final _descricao = TextEditingController();
  final _precoFinal = TextEditingController();
  final _selecionados = <String, int>{};

  double _valorNormalTotal = 0;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final servicos = await _repository.listarServicosAtivos();
      if (mounted) {
        setState(() {
          _servicos = servicos;
          _carregando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _carregando = false);
        _mostrarErro(e.toString());
      }
    }
  }

  void _mostrarErro(String erro) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(erro), behavior: SnackBarBehavior.floating),
    );
  }

  void _recalcularTotal() {
    double total = 0;
    for (final servico in _servicos) {
      final id = servico['id'] as String;
      final qtd = _selecionados[id] ?? 0;
      if (qtd > 0) {
        total += (servico['preco'] as num).toDouble() * qtd;
      }
    }
    setState(() {
      _valorNormalTotal = total;
    });
  }

  Future<void> _salvar() async {
    final nome = _nome.text.trim();
    if (nome.isEmpty) {
      _mostrarErro('Informe o nome do pacote.');
      return;
    }
    if (_selecionados.isEmpty) {
      _mostrarErro('Selecione ao menos um serviço.');
      return;
    }
    final precoParseado = double.tryParse(
      _precoFinal.text.replaceAll(',', '.'),
    );
    if (precoParseado == null || precoParseado < 0) {
      _mostrarErro('Informe um preço final válido.');
      return;
    }

    setState(() => _carregando = true);

    try {
      await _repository.salvarModelo(
        PacoteEntrada(
          nome: nome,
          descricao: _descricao.text.trim(),
          categoria: 'Pacotes', // Categoria fixa simplificada
          precoPacote: precoParseado,
          validadeDias: 90, // Padrão
          itens: _selecionados.entries.where((e) => e.value > 0).map((e) {
            return PacoteItemEntrada(servicoId: e.key, quantidade: e.value);
          }).toList(),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _carregando = false);
        _mostrarErro(e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Novo pacote'),
        actions: [
          if (!_carregando)
            TextButton(onPressed: _salvar, child: const Text('Salvar')),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nome,
                    decoration: const InputDecoration(
                      labelText: 'Nome do pacote *',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _descricao,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Descrição (opcional)',
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Serviços incluídos',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (_servicos.isEmpty)
                    const Text('Nenhum serviço ativo encontrado.')
                  else
                    ..._servicos.map((servico) {
                      final id = servico['id'] as String;
                      final precoUnit = (servico['preco'] as num).toDouble();
                      final qtd = _selecionados[id] ?? 0;
                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: qtd > 0,
                        title: Text(servico['nome'] as String),
                        subtitle: Text(
                          qtd == 0
                              ? 'R\$ ${precoUnit.toStringAsFixed(2)} cada'
                              : 'Qtd: $qtd • Subtotal: R\$ ${(precoUnit * qtd).toStringAsFixed(2)}',
                        ),
                        secondary: qtd == 0
                            ? null
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        if (qtd > 1) {
                                          _selecionados[id] = qtd - 1;
                                        } else {
                                          _selecionados.remove(id);
                                        }
                                      });
                                      _recalcularTotal();
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline),
                                    onPressed: () {
                                      setState(() {
                                        _selecionados[id] = qtd + 1;
                                      });
                                      _recalcularTotal();
                                    },
                                  ),
                                ],
                              ),
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selecionados[id] = 1;
                            } else {
                              _selecionados.remove(id);
                            }
                          });
                          _recalcularTotal();
                        },
                      );
                    }),
                  const SizedBox(height: 24),
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Resumo Financeiro',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Valor normal (soma dos serviços): R\$ ${_valorNormalTotal.toStringAsFixed(2)}',
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _precoFinal,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Preço final do pacote *',
                              filled: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
