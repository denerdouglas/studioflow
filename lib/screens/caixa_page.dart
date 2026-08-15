import 'package:flutter/material.dart';

import '../repositories/caixa_repository.dart';

class CaixaPage extends StatefulWidget {
  const CaixaPage({super.key});

  @override
  State<CaixaPage> createState() => _CaixaPageState();
}

class _CaixaPageState extends State<CaixaPage> {
  Color get _corPrincipal => Theme.of(context).colorScheme.primary;
  Color get _corFundo => Theme.of(context).colorScheme.surface;
  Color get _textoEscuro => Theme.of(context).colorScheme.onSurface;
  Color get _textoClaro => Theme.of(context).colorScheme.onSurfaceVariant;
  static const Color _verde = Color(0xFF15996B);
  static const Color _vermelho = Color(0xFFD64D64);

  final CaixaRepository _repository = CaixaRepository();

  DateTime _dataSelecionada = DateTime.now();

  List<MovimentoFinanceiroRegistro> _movimentosTodos = [];

  String _abaSelecionada = 'geral';

  List<MovimentoFinanceiroRegistro> get _movimentos {
    if (_abaSelecionada == 'servico') {
      return _movimentosTodos
          .where((m) => m.centroResultado == 'salao')
          .toList();
    } else if (_abaSelecionada == 'loja') {
      return _movimentosTodos
          .where((m) => m.centroResultado == 'loja')
          .toList();
    } else if (_abaSelecionada == 'consignado') {
      return _movimentosTodos
          .where((m) => m.centroResultado == 'consignado')
          .toList();
    }
    return _movimentosTodos;
  }

  ResumoCaixa get _resumoAtual {
    double entradas = 0;
    double saidas = 0;
    int qtdEntradas = 0;
    int qtdSaidas = 0;
    for (final item in _movimentos) {
      if (item.entrada) {
        entradas += item.valor;
        qtdEntradas++;
      } else {
        saidas += item.valor;
        qtdSaidas++;
      }
    }
    return ResumoCaixa(
      totalEntradas: entradas,
      totalSaidas: saidas,
      saldo: entradas - saidas,
      quantidadeEntradas: qtdEntradas,
      quantidadeSaidas: qtdSaidas,
    );
  }

  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregarCaixa();
  }

  Future<void> _carregarCaixa() async {
    try {
      final resultados = await Future.wait([
        _repository.listarPorDia(_dataSelecionada),
        _repository.resumoDoDia(_dataSelecionada),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _movimentosTodos = resultados[0] as List<MovimentoFinanceiroRegistro>;

        _carregando = false;
        _erro = null;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
        _erro = 'Não foi possível carregar o caixa.';
      });
    }
  }

  Future<void> _selecionarData() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _dataSelecionada,
      firstDate: DateTime(2025),
      lastDate: DateTime(2035),
      locale: const Locale('pt', 'BR'),
    );

    if (data == null) {
      return;
    }

    setState(() {
      _dataSelecionada = data;
      _carregando = true;
    });

    await _carregarCaixa();
  }

  Future<void> _abrirNovaMovimentacao() async {
    final movimento = await showModalBottomSheet<MovimentoFinanceiroRegistro>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return NovaMovimentacaoSheet(dataBase: _dataSelecionada);
      },
    );

    if (movimento == null) {
      return;
    }

    try {
      await _repository.inserir(movimento);

      setState(() {
        _carregando = true;
      });

      await _carregarCaixa();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            movimento.entrada
                ? 'Entrada registrada com sucesso.'
                : 'Saída registrada com sucesso.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (erro) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível salvar a movimentação.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _abrirOpcoesMovimento(
    MovimentoFinanceiroRegistro movimento,
  ) async {
    final acao = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return OpcoesMovimentoSheet(movimento: movimento);
      },
    );

    if (acao == null) {
      return;
    }

    if (acao == 'editar') {
      await _editarMovimento(movimento);

      return;
    }

    if (acao == 'excluir') {
      final confirmou = await _confirmarExclusao(movimento);

      if (!confirmou) {
        return;
      }

      try {
        await _repository.excluir(movimento.id);

        setState(() {
          _carregando = true;
        });

        await _carregarCaixa();

        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Movimentação excluída.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (erro) {
        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível excluir a movimentação.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _editarMovimento(MovimentoFinanceiroRegistro movimento) async {
    final atualizado = await showModalBottomSheet<MovimentoFinanceiroRegistro>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return NovaMovimentacaoSheet(
          dataBase: movimento.data,
          movimentoInicial: movimento,
        );
      },
    );

    if (atualizado == null) {
      return;
    }

    try {
      await _repository.atualizar(atualizado);

      setState(() {
        _carregando = true;
      });

      await _carregarCaixa();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Movimentação atualizada.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (erro) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível atualizar a movimentação.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<bool> _confirmarExclusao(MovimentoFinanceiroRegistro movimento) async {
    final resposta = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: Text('Excluir movimentação?'),
          content: Text('Deseja excluir “${movimento.descricao}”?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              style: FilledButton.styleFrom(backgroundColor: _vermelho),
              child: Text('Excluir'),
            ),
          ],
        );
      },
    );

    return resposta ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _corFundo,
      body: SafeArea(
        child: Column(
          children: [
            _cabecalho(),
            _seletorData(),
            SizedBox(height: 14),
            _seletorAbas(),
            SizedBox(height: 14),
            _resumoFinanceiro(),
            SizedBox(height: 14),
            Expanded(child: _conteudo()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: _abrirNovaMovimentacao,
        backgroundColor: _corPrincipal,
        foregroundColor: Colors.white,
        icon: Icon(Icons.add),
        label: Text(
          'Nova movimentação',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _cabecalho() {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Caixa',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: _textoEscuro,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Entradas, saídas e saldo diário',
                  style: TextStyle(fontSize: 13, color: _textoClaro),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _seletorData() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          onTap: _selecionarData,
          borderRadius: BorderRadius.circular(17),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: const Color(0xFFE8E1EE)),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_month_outlined, color: _corPrincipal),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _formatarData(_dataSelecionada),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _textoEscuro,
                    ),
                  ),
                ),
                Icon(Icons.keyboard_arrow_down, color: _textoClaro),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _seletorAbas() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _abaCard('Geral', 'geral'),
          const SizedBox(width: 8),
          _abaCard('Serviços', 'servico'),
          const SizedBox(width: 8),
          _abaCard('Loja', 'loja'),
          const SizedBox(width: 8),
          _abaCard('Consignado', 'consignado'),
        ],
      ),
    );
  }

  Widget _abaCard(String titulo, String valor) {
    final selecionado = _abaSelecionada == valor;
    return InkWell(
      onTap: () {
        setState(() {
          _abaSelecionada = valor;
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selecionado ? _corPrincipal : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selecionado ? _corPrincipal : Colors.grey.shade300,
          ),
        ),
        child: Text(
          titulo,
          style: TextStyle(
            color: selecionado ? Colors.white : _textoEscuro,
            fontWeight: selecionado ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _resumoFinanceiro() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Color(0xFF9A78C5),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Saldo do dia',
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
                SizedBox(height: 8),
                Text(
                  'R\$ ${_resumoAtual.saldo.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ResumoCard(
                  titulo: 'Entradas',
                  valor: _resumoAtual.totalEntradas,
                  quantidade: _resumoAtual.quantidadeEntradas,
                  icone: Icons.arrow_downward_rounded,
                  cor: _verde,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _ResumoCard(
                  titulo: 'Saídas',
                  valor: _resumoAtual.totalSaidas,
                  quantidade: _resumoAtual.quantidadeSaidas,
                  icone: Icons.arrow_upward_rounded,
                  cor: _vermelho,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _conteudo() {
    if (_carregando) {
      return Center(child: CircularProgressIndicator(color: _corPrincipal));
    }

    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 65, color: _vermelho),
              SizedBox(height: 14),
              Text(
                _erro!,
                textAlign: TextAlign.center,
                style: TextStyle(color: _textoEscuro),
              ),
              SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _carregando = true;
                    _erro = null;
                  });

                  _carregarCaixa();
                },
                icon: Icon(Icons.refresh),
                label: Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    if (_movimentos.isEmpty) {
      return Center(
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
                'Nenhuma movimentação neste dia',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: _textoEscuro,
                ),
              ),
              SizedBox(height: 7),
              Text(
                'Toque em “Nova movimentação” para registrar uma entrada ou saída.',
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
      onRefresh: _carregarCaixa,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
        itemCount: _movimentos.length,
        separatorBuilder: (_, _) {
          return SizedBox(height: 10);
        },
        itemBuilder: (context, index) {
          final movimento = _movimentos[index];

          return _MovimentoCard(
            movimento: movimento,
            onTap: () {
              _abrirOpcoesMovimento(movimento);
            },
          );
        },
      ),
    );
  }

  String _formatarData(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');

    final mes = data.month.toString().padLeft(2, '0');

    return '$dia/$mes/${data.year}';
  }
}

class _ResumoCard extends StatelessWidget {
  final String titulo;
  final double valor;
  final int quantidade;
  final IconData icone;
  final Color cor;

  const _ResumoCard({
    required this.titulo,
    required this.valor,
    required this.quantidade,
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
        border: Border.all(color: const Color(0xFFE8E1EE)),
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
          SizedBox(height: 10),
          Text(
            titulo,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'R\$ ${valor.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          SizedBox(height: 3),
          Text(
            '$quantidade movimentações',
            style: TextStyle(fontSize: 11, color: Color(0xFF968AA5)),
          ),
        ],
      ),
    );
  }
}

class _MovimentoCard extends StatelessWidget {
  final MovimentoFinanceiroRegistro movimento;
  final VoidCallback onTap;

  const _MovimentoCard({required this.movimento, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cor = movimento.entrada
        ? const Color(0xFF15996B)
        : const Color(0xFFD64D64);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE8E1EE)),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  movimento.entrada
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  color: cor,
                ),
              ),
              SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movimento.descricao,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '${movimento.categoria} • '
                      '${movimento.formaPagamento}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${movimento.entrada ? '+' : '-'} '
                    'R\$ ${movimento.valor.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: cor,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    _formatarHora(movimento.data),
                    style: TextStyle(fontSize: 11, color: Color(0xFF968AA5)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatarHora(DateTime data) {
    final hora = data.hour.toString().padLeft(2, '0');

    final minuto = data.minute.toString().padLeft(2, '0');

    return '$hora:$minuto';
  }
}

class OpcoesMovimentoSheet extends StatelessWidget {
  final MovimentoFinanceiroRegistro movimento;

  const OpcoesMovimentoSheet({super.key, required this.movimento});

  @override
  Widget build(BuildContext context) {
    final cor = movimento.entrada
        ? const Color(0xFF15996B)
        : const Color(0xFFD64D64);

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
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
          SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  movimento.entrada
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  color: cor,
                ),
              ),
              SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movimento.descricao,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'R\$ ${movimento.valor.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: cor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 22),
          _OpcaoMovimento(
            titulo: 'Editar movimentação',
            icone: Icons.edit_outlined,
            cor: Theme.of(context).colorScheme.primary,
            onTap: () {
              Navigator.pop(context, 'editar');
            },
          ),
          _OpcaoMovimento(
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

class _OpcaoMovimento extends StatelessWidget {
  final String titulo;
  final IconData icone;
  final Color cor;
  final VoidCallback onTap;

  const _OpcaoMovimento({
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
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      trailing: Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class NovaMovimentacaoSheet extends StatefulWidget {
  final DateTime dataBase;
  final MovimentoFinanceiroRegistro? movimentoInicial;

  const NovaMovimentacaoSheet({
    super.key,
    required this.dataBase,
    this.movimentoInicial,
  });

  @override
  State<NovaMovimentacaoSheet> createState() => _NovaMovimentacaoSheetState();
}

class _NovaMovimentacaoSheetState extends State<NovaMovimentacaoSheet> {
  Color get _corPrincipal => Theme.of(context).colorScheme.primary;

  Color get _corFundo => Theme.of(context).colorScheme.surface;

  final TextEditingController _descricaoController = TextEditingController();

  final TextEditingController _valorController = TextEditingController();

  final TextEditingController _observacoesController = TextEditingController();

  String _tipo = 'entrada';
  String _categoria = 'Serviços';
  String _formaPagamento = 'Dinheiro';

  late DateTime _dataSelecionada;

  final List<String> _categorias = const [
    'Serviços',
    'Produtos',
    'Material',
    'Aluguel',
    'Água',
    'Luz',
    'Internet',
    'Manutenção',
    'Comissão',
    'Outros',
  ];

  final List<String> _formasPagamento = const [
    'Dinheiro',
    'Pix',
    'Débito',
    'Crédito',
    'Transferência',
    'Outro',
  ];

  @override
  void initState() {
    super.initState();

    _dataSelecionada = widget.dataBase;

    final movimento = widget.movimentoInicial;

    if (movimento != null) {
      _tipo = movimento.tipo;
      _categoria = movimento.categoria;
      _formaPagamento = movimento.formaPagamento;

      _descricaoController.text = movimento.descricao;

      _valorController.text = movimento.valor.toStringAsFixed(2);

      _observacoesController.text = movimento.observacoes;
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
      firstDate: DateTime(2025),
      lastDate: DateTime(2035),
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

    final textoValor = _valorController.text.trim().replaceAll(',', '.');

    final valor = double.tryParse(textoValor);

    if (descricao.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe uma descrição.'),
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

    final dataMovimento = DateTime(
      _dataSelecionada.year,
      _dataSelecionada.month,
      _dataSelecionada.day,
      agora.hour,
      agora.minute,
      agora.second,
    );

    final existente = widget.movimentoInicial;

    final movimento = MovimentoFinanceiroRegistro(
      id: existente?.id ?? agora.microsecondsSinceEpoch.toString(),
      tipo: _tipo,
      descricao: descricao,
      valor: valor,
      formaPagamento: _formaPagamento,
      status: existente?.status ?? 'pago',
      data: dataMovimento,
      dataCriacao: existente?.dataCriacao ?? agora,
      categoria: _categoria,
      clienteId: existente?.clienteId,
      profissionalId: existente?.profissionalId,
      agendamentoId: existente?.agendamentoId,
      servicoId: existente?.servicoId,
      usuarioResponsavelId: existente?.usuarioResponsavelId,
      observacoes: _observacoesController.text.trim(),
    );

    Navigator.pop(context, movimento);
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;

    final editando = widget.movimentoInicial != null;

    return Container(
      padding: EdgeInsets.fromLTRB(22, 22, 22, teclado + 25),
      decoration: BoxDecoration(
        color: _corFundo,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
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
            SizedBox(height: 20),
            Text(
              editando ? 'Editar movimentação' : 'Nova movimentação',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Registre uma entrada ou saída do caixa.',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: 22),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'entrada',
                  label: Text('Entrada'),
                  icon: Icon(Icons.arrow_downward_rounded),
                ),
                ButtonSegment(
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
            SizedBox(height: 16),
            TextField(
              controller: _descricaoController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Descrição',
                prefixIcon: Icon(Icons.description_outlined),
              ),
            ),
            SizedBox(height: 14),
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
            SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _categoria,
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
            SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _formaPagamento,
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
            SizedBox(height: 14),
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
            SizedBox(height: 14),
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
            SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _salvar,
              icon: Icon(Icons.save_outlined),
              label: Text(
                editando ? 'Salvar alterações' : 'Salvar movimentação',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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

  String _formatarData(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');

    final mes = data.month.toString().padLeft(2, '0');

    return '$dia/$mes/${data.year}';
  }
}
