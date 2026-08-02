import 'package:flutter/material.dart';

import '../repositories/financeiro_repository.dart';

class FinanceiroPage extends StatefulWidget {
  const FinanceiroPage({super.key});

  @override
  State<FinanceiroPage> createState() => _FinanceiroPageState();
}

class _FinanceiroPageState extends State<FinanceiroPage> {
  static const Color _corPrincipal = Color(0xFF70569A);

  static const Color _corFundo = Color(0xFFF9F6FC);

  static const Color _textoEscuro = Color(0xFF2D2140);

  static const Color _textoClaro = Color(0xFF766A85);

  static const Color _verde = Color(0xFF15996B);

  static const Color _vermelho = Color(0xFFD64D64);

  static const Color _laranja = Color(0xFFE58A25);

  final FinanceiroRepository _repository = FinanceiroRepository();

  final TextEditingController _pesquisaController = TextEditingController();

  List<MovimentacaoFinanceiraRegistro> _movimentacoes = [];

  ResumoFinanceiro _resumo = ResumoFinanceiro.vazio();

  bool _carregando = true;

  String _pesquisa = '';
  String _filtroTipo = 'todos';
  String _filtroStatus = 'todos';
  String? _erro;

  DateTime? _dataInicial;
  DateTime? _dataFinal;

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
        _repository.listar(
          dataInicial: _dataInicial,
          dataFinal: _dataFinal,
          tipo: _filtroTipo,
          status: _filtroStatus,
        ),
        _repository.resumo(),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _movimentacoes = resultados[0] as List<MovimentacaoFinanceiraRegistro>;

        _resumo = resultados[1] as ResumoFinanceiro;

        _carregando = false;
        _erro = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
        _erro = 'Não foi possível carregar o financeiro.';
      });
    }
  }

  List<MovimentacaoFinanceiraRegistro> get _movimentacoesFiltradas {
    final texto = _pesquisa.trim().toLowerCase();

    if (texto.isEmpty) {
      return _movimentacoes;
    }

    return _movimentacoes.where((movimentacao) {
      return movimentacao.descricao.toLowerCase().contains(texto) ||
          movimentacao.categoria.toLowerCase().contains(texto) ||
          movimentacao.formaPagamento.toLowerCase().contains(texto);
    }).toList();
  }

  Future<void> _novaMovimentacao() async {
    final movimentacao =
        await showModalBottomSheet<MovimentacaoFinanceiraRegistro>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) {
            return const MovimentacaoFinanceiraFormSheet();
          },
        );

    if (movimentacao == null) {
      return;
    }

    try {
      await _repository.inserir(movimentacao);

      await _atualizarAposAcao('Movimentação registrada com sucesso.');
    } catch (_) {
      _mostrarErro('Não foi possível salvar a movimentação.');
    }
  }

  Future<void> _editarMovimentacao(
    MovimentacaoFinanceiraRegistro movimentacao,
  ) async {
    final atualizada =
        await showModalBottomSheet<MovimentacaoFinanceiraRegistro>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) {
            return MovimentacaoFinanceiraFormSheet(
              movimentacaoInicial: movimentacao,
            );
          },
        );

    if (atualizada == null) {
      return;
    }

    try {
      await _repository.atualizar(atualizada);

      await _atualizarAposAcao('Movimentação atualizada.');
    } catch (_) {
      _mostrarErro('Não foi possível atualizar a movimentação.');
    }
  }

  Future<void> _alterarStatus(
    MovimentacaoFinanceiraRegistro movimentacao,
  ) async {
    final novoStatus = movimentacao.status == 'pago' ? 'pendente' : 'pago';

    try {
      await _repository.alterarStatus(id: movimentacao.id, status: novoStatus);

      await _atualizarAposAcao(
        novoStatus == 'pago'
            ? 'Movimentação marcada como paga.'
            : 'Movimentação marcada como pendente.',
      );
    } catch (_) {
      _mostrarErro('Não foi possível alterar o status.');
    }
  }

  Future<void> _excluirMovimentacao(
    MovimentacaoFinanceiraRegistro movimentacao,
  ) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Excluir movimentação?'),
          content: Text('Deseja excluir “${movimentacao.descricao}”?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              style: FilledButton.styleFrom(backgroundColor: _vermelho),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmou != true) {
      return;
    }

    try {
      await _repository.excluir(movimentacao.id);

      await _atualizarAposAcao('Movimentação excluída.');
    } catch (_) {
      _mostrarErro('Não foi possível excluir a movimentação.');
    }
  }

  Future<void> _abrirOpcoes(MovimentacaoFinanceiraRegistro movimentacao) async {
    final acao = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return OpcoesFinanceiroSheet(movimentacao: movimentacao);
      },
    );

    if (acao == 'editar') {
      await _editarMovimentacao(movimentacao);
    }

    if (acao == 'status') {
      await _alterarStatus(movimentacao);
    }

    if (acao == 'excluir') {
      await _excluirMovimentacao(movimentacao);
    }
  }

  Future<void> _selecionarPeriodo() async {
    final agora = DateTime.now();

    final periodo = await showDateRangePicker(
      context: context,
      firstDate: DateTime(agora.year - 5),
      lastDate: DateTime(agora.year + 5),
      initialDateRange: _dataInicial != null && _dataFinal != null
          ? DateTimeRange(start: _dataInicial!, end: _dataFinal!)
          : null,
      locale: const Locale('pt', 'BR'),
    );

    if (periodo == null) {
      return;
    }

    setState(() {
      _dataInicial = periodo.start;
      _dataFinal = periodo.end;
      _carregando = true;
    });

    await _carregarDados();
  }

  void _limparPeriodo() {
    setState(() {
      _dataInicial = null;
      _dataFinal = null;
      _carregando = true;
    });

    _carregarDados();
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

  String _formatarData(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');

    final mes = data.month.toString().padLeft(2, '0');

    return '$dia/$mes/${data.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _corFundo,
      appBar: AppBar(
        backgroundColor: _corFundo,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Financeiro',
          style: TextStyle(fontWeight: FontWeight.bold, color: _textoEscuro),
        ),
        actions: [
          IconButton(
            tooltip: 'Selecionar período',
            onPressed: _selecionarPeriodo,
            icon: const Icon(Icons.date_range_outlined, color: _corPrincipal),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: () {
              setState(() {
                _carregando = true;
              });

              _carregarDados();
            },
            icon: const Icon(Icons.refresh, color: _corPrincipal),
          ),
        ],
      ),
      body: Column(
        children: [
          _resumoFinanceiro(),
          const SizedBox(height: 12),
          _filtros(),
          const SizedBox(height: 10),
          Expanded(child: _conteudo()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
      heroTag: null,
      onPressed: _novaMovimentacao,
        backgroundColor: _corPrincipal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text(
          'Nova movimentação',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _resumoFinanceiro() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
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
                  'Saldo atual',
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _formatarDinheiro(_resumo.saldo),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Entradas: '
                  '${_formatarDinheiro(_resumo.totalEntradas)}'
                  ' • Saídas: '
                  '${_formatarDinheiro(_resumo.totalSaidas)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ResumoFinanceiroCard(
                  titulo: 'Entradas',
                  valor: _formatarDinheiro(_resumo.totalEntradas),
                  icone: Icons.arrow_downward_rounded,
                  cor: _verde,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ResumoFinanceiroCard(
                  titulo: 'Saídas',
                  valor: _formatarDinheiro(_resumo.totalSaidas),
                  icone: Icons.arrow_upward_rounded,
                  cor: _vermelho,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ResumoFinanceiroCard(
                  titulo: 'A receber',
                  valor: _formatarDinheiro(_resumo.contasReceber),
                  icone: Icons.receipt_long_outlined,
                  cor: const Color(0xFF3078C5),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ResumoFinanceiroCard(
                  titulo: 'A pagar',
                  valor: _formatarDinheiro(_resumo.contasPagar),
                  icone: Icons.payments_outlined,
                  cor: _laranja,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filtros() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        children: [
          TextField(
            controller: _pesquisaController,
            onChanged: (valor) {
              setState(() {
                _pesquisa = valor;
              });
            },
            decoration: InputDecoration(
              hintText: 'Buscar descrição, categoria ou pagamento...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _pesquisa.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _pesquisaController.clear();

                        setState(() {
                          _pesquisa = '';
                        });
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _filtroTipo,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: const [
                    DropdownMenuItem(value: 'todos', child: Text('Todos')),
                    DropdownMenuItem(value: 'entrada', child: Text('Entradas')),
                    DropdownMenuItem(value: 'saida', child: Text('Saídas')),
                  ],
                  onChanged: (valor) {
                    if (valor == null) {
                      return;
                    }

                    setState(() {
                      _filtroTipo = valor;
                      _carregando = true;
                    });

                    _carregarDados();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _filtroStatus,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'todos', child: Text('Todos')),
                    DropdownMenuItem(value: 'pago', child: Text('Pago')),
                    DropdownMenuItem(
                      value: 'pendente',
                      child: Text('Pendente'),
                    ),
                  ],
                  onChanged: (valor) {
                    if (valor == null) {
                      return;
                    }

                    setState(() {
                      _filtroStatus = valor;
                      _carregando = true;
                    });

                    _carregarDados();
                  },
                ),
              ),
            ],
          ),
          if (_dataInicial != null && _dataFinal != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: const Color(0xFFE6DFF0)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.date_range_outlined,
                    size: 20,
                    color: _corPrincipal,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_formatarData(_dataInicial!)} até '
                      '${_formatarData(_dataFinal!)}',
                      style: const TextStyle(
                        color: _textoEscuro,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Limpar período',
                    onPressed: _limparPeriodo,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _conteudo() {
    if (_carregando) {
      return const Center(
        child: CircularProgressIndicator(color: _corPrincipal),
      );
    }

    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: _vermelho),
              const SizedBox(height: 14),
              Text(
                _erro!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: _textoEscuro),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _carregando = true;
                    _erro = null;
                  });

                  _carregarDados();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    final movimentacoes = _movimentacoesFiltradas;

    if (movimentacoes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 70,
                color: Color(0xFFB6A9C3),
              ),
              SizedBox(height: 16),
              Text(
                'Nenhuma movimentação encontrada',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: _textoEscuro,
                ),
              ),
              SizedBox(height: 7),
              Text(
                'Toque em “Nova movimentação” para registrar a primeira.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _textoClaro),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: _corPrincipal,
      onRefresh: _carregarDados,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 110),
        itemCount: movimentacoes.length,
        separatorBuilder: (_, _) {
          return const SizedBox(height: 10);
        },
        itemBuilder: (context, index) {
          final movimentacao = movimentacoes[index];

          return _MovimentacaoFinanceiraCard(
            movimentacao: movimentacao,
            onTap: () {
              _abrirOpcoes(movimentacao);
            },
          );
        },
      ),
    );
  }
}

class _ResumoFinanceiroCard extends StatelessWidget {
  final String titulo;
  final String valor;
  final IconData icone;
  final Color cor;

  const _ResumoFinanceiroCard({
    required this.titulo,
    required this.valor,
    required this.icone,
    required this.cor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6DFF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icone, color: cor),
          ),
          const SizedBox(height: 10),
          Text(
            titulo,
            style: const TextStyle(fontSize: 12, color: Color(0xFF766A85)),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D2140),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MovimentacaoFinanceiraCard extends StatelessWidget {
  final MovimentacaoFinanceiraRegistro movimentacao;

  final VoidCallback onTap;

  const _MovimentacaoFinanceiraCard({
    required this.movimentacao,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final entrada = movimentacao.ehEntrada;

    final cor = entrada ? const Color(0xFF15996B) : const Color(0xFFD64D64);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE6DFF0)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  entrada
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  color: cor,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            movimentacao.descricao,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2D2140),
                            ),
                          ),
                        ),
                        _StatusFinanceiro(status: movimentacao.status),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      movimentacao.categoria,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF766A85),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _InformacaoFinanceira(
                          icone: Icons.payments_outlined,
                          texto: movimentacao.formaPagamento.isEmpty
                              ? 'Não informado'
                              : movimentacao.formaPagamento,
                        ),
                        _InformacaoFinanceira(
                          icone: Icons.calendar_month_outlined,
                          texto: _formatarData(movimentacao.data),
                        ),
                      ],
                    ),
                    if (movimentacao.observacoes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        movimentacao.observacoes,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF968AA5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${entrada ? '+' : '-'} '
                    'R\$ ${movimentacao.valor.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: cor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Icon(Icons.more_vert, color: Color(0xFF968AA5)),
                ],
              ),
            ],
          ),
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

class _StatusFinanceiro extends StatelessWidget {
  final String status;

  const _StatusFinanceiro({required this.status});

  @override
  Widget build(BuildContext context) {
    final pago = status == 'pago';

    final cor = pago ? const Color(0xFF15996B) : const Color(0xFFE58A25);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        pago ? 'Pago' : 'Pendente',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cor),
      ),
    );
  }
}

class _InformacaoFinanceira extends StatelessWidget {
  final IconData icone;
  final String texto;

  const _InformacaoFinanceira({required this.icone, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF3EDF8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 14, color: const Color(0xFF70569A)),
          const SizedBox(width: 4),
          Text(
            texto,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF70569A),
            ),
          ),
        ],
      ),
    );
  }
}

class OpcoesFinanceiroSheet extends StatelessWidget {
  final MovimentacaoFinanceiraRegistro movimentacao;

  const OpcoesFinanceiroSheet({super.key, required this.movimentacao});

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
            movimentacao.descricao,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D2140),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'R\$ ${movimentacao.valor.toStringAsFixed(2)}',
            style: const TextStyle(color: Color(0xFF766A85)),
          ),
          const SizedBox(height: 22),
          _OpcaoFinanceiro(
            titulo: 'Editar movimentação',
            icone: Icons.edit_outlined,
            cor: const Color(0xFF70569A),
            onTap: () {
              Navigator.pop(context, 'editar');
            },
          ),
          _OpcaoFinanceiro(
            titulo: movimentacao.status == 'pago'
                ? 'Marcar como pendente'
                : 'Marcar como pago',
            icone: movimentacao.status == 'pago'
                ? Icons.schedule_outlined
                : Icons.check_circle_outline,
            cor: movimentacao.status == 'pago'
                ? const Color(0xFFE58A25)
                : const Color(0xFF15996B),
            onTap: () {
              Navigator.pop(context, 'status');
            },
          ),
          _OpcaoFinanceiro(
            titulo: 'Excluir movimentação',
            icone: Icons.delete_outline,
            cor: const Color(0xFFD64D64),
            onTap: () {
              Navigator.pop(context, 'excluir');
            },
          ),
        ],
      ),
    );
  }
}

class _OpcaoFinanceiro extends StatelessWidget {
  final String titulo;
  final IconData icone;
  final Color cor;
  final VoidCallback onTap;

  const _OpcaoFinanceiro({
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

class MovimentacaoFinanceiraFormSheet extends StatefulWidget {
  final MovimentacaoFinanceiraRegistro? movimentacaoInicial;

  const MovimentacaoFinanceiraFormSheet({super.key, this.movimentacaoInicial});

  @override
  State<MovimentacaoFinanceiraFormSheet> createState() =>
      _MovimentacaoFinanceiraFormSheetState();
}

class _MovimentacaoFinanceiraFormSheetState
    extends State<MovimentacaoFinanceiraFormSheet> {
  static const Color _corPrincipal = Color(0xFF70569A);

  static const Color _corFundo = Color(0xFFF9F6FC);

  final TextEditingController _descricaoController = TextEditingController();

  final TextEditingController _valorController = TextEditingController();

  final TextEditingController _observacoesController = TextEditingController();

  String _tipo = 'entrada';
  String _categoria = 'Serviços';
  String _formaPagamento = 'Pix';
  String _status = 'pago';

  DateTime _dataSelecionada = DateTime.now();

  final List<String> _categorias = const [
    'Serviços',
    'Produtos',
    'Venda de produtos',
    'Material',
    'Aluguel',
    'Água',
    'Luz',
    'Internet',
    'Manutenção',
    'Comissão',
    'Impostos',
    'Marketing',
    'Transporte',
    'Outros',
  ];

  final List<String> _formasPagamento = const [
    'Pix',
    'Dinheiro',
    'Débito',
    'Crédito',
    'Transferência',
    'Boleto',
    'Outro',
  ];

  @override
  void initState() {
    super.initState();

    final movimentacao = widget.movimentacaoInicial;

    if (movimentacao == null) {
      return;
    }

    _descricaoController.text = movimentacao.descricao;

    _valorController.text = movimentacao.valor.toStringAsFixed(2);

    _observacoesController.text = movimentacao.observacoes;

    _tipo = movimentacao.ehEntrada ? 'entrada' : 'saida';

    _categoria = movimentacao.categoria;

    _formaPagamento = movimentacao.formaPagamento.isEmpty
        ? 'Pix'
        : movimentacao.formaPagamento;

    _status = movimentacao.status;

    _dataSelecionada = movimentacao.data;

    if (!_categorias.contains(_categoria)) {
      _categoria = 'Outros';
    }

    if (!_formasPagamento.contains(_formaPagamento)) {
      _formaPagamento = 'Outro';
    }
  }

  @override
  void dispose() {
    _descricaoController.dispose();
    _valorController.dispose();
    _observacoesController.dispose();

    super.dispose();
  }

  Future<void> _selecionarData() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _dataSelecionada,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime(DateTime.now().year + 5),
      locale: const Locale('pt', 'BR'),
    );

    if (data == null) {
      return;
    }

    setState(() {
      _dataSelecionada = DateTime(
        data.year,
        data.month,
        data.day,
        _dataSelecionada.hour,
        _dataSelecionada.minute,
      );
    });
  }

  void _salvar() {
    final descricao = _descricaoController.text.trim();

    final valor = double.tryParse(
      _valorController.text.trim().replaceAll(',', '.'),
    );

    if (descricao.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe a descrição da movimentação.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      return;
    }

    if (valor == null || valor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe um valor válido.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      return;
    }

    final agora = DateTime.now();

    final dataMovimentacao = DateTime(
      _dataSelecionada.year,
      _dataSelecionada.month,
      _dataSelecionada.day,
      agora.hour,
      agora.minute,
      agora.second,
    );

    final existente = widget.movimentacaoInicial;

    final movimentacao = MovimentacaoFinanceiraRegistro(
      id: existente?.id ?? agora.microsecondsSinceEpoch.toString(),
      tipo: _tipo,
      descricao: descricao,
      valor: valor,
      formaPagamento: _formaPagamento,
      status: _status,
      data: dataMovimentacao,
      dataCriacao: existente?.dataCriacao ?? agora,
      categoria: _categoria,
      clienteId: existente?.clienteId,
      profissionalId: existente?.profissionalId,
      agendamentoId: existente?.agendamentoId,
      servicoId: existente?.servicoId,
      usuarioResponsavelId: existente?.usuarioResponsavelId,
      observacoes: _observacoesController.text.trim(),
    );

    Navigator.pop(context, movimentacao);
  }

  String _formatarData(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');

    final mes = data.month.toString().padLeft(2, '0');

    return '$dia/$mes/${data.year}';
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;

    final editando = widget.movimentacaoInicial != null;

    return Container(
      padding: EdgeInsets.fromLTRB(22, 22, 22, teclado + 25),
      decoration: const BoxDecoration(
        color: _corFundo,
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
              editando ? 'Editar movimentação' : 'Nova movimentação',
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D2140),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Registre uma entrada ou saída financeira.',
              style: TextStyle(fontSize: 13, color: Color(0xFF766A85)),
            ),
            const SizedBox(height: 22),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'entrada',
                  label: Text('Entrada'),
                  icon: Icon(Icons.arrow_downward_rounded),
                ),
                ButtonSegment<String>(
                  value: 'saida',
                  label: Text('Saída'),
                  icon: Icon(Icons.arrow_upward_rounded),
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
              controller: _descricaoController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Descrição',
                prefixIcon: Icon(Icons.description_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _valorController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Valor',
                prefixText: 'R\$ ',
                prefixIcon: Icon(Icons.attach_money),
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
                  child: Text(categoria, overflow: TextOverflow.ellipsis),
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
              initialValue: _formaPagamento,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Forma de pagamento',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              items: _formasPagamento.map((forma) {
                return DropdownMenuItem(value: forma, child: Text(forma));
              }).toList(),
              onChanged: (valor) {
                if (valor == null) {
                  return;
                }

                setState(() {
                  _formaPagamento = valor;
                });
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(
                labelText: 'Status',
                prefixIcon: Icon(Icons.check_circle_outline),
              ),
              items: const [
                DropdownMenuItem(value: 'pago', child: Text('Pago')),
                DropdownMenuItem(value: 'pendente', child: Text('Pendente')),
              ],
              onChanged: (valor) {
                if (valor == null) {
                  return;
                }

                setState(() {
                  _status = valor;
                });
              },
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: _selecionarData,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Data',
                  prefixIcon: Icon(Icons.calendar_month_outlined),
                ),
                child: Text(_formatarData(_dataSelecionada)),
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
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _salvar,
              icon: const Icon(Icons.save_outlined),
              label: Text(
                editando ? 'Salvar alterações' : 'Salvar movimentação',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _corPrincipal,
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
