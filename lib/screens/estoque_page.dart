import 'package:flutter/material.dart';

import '../models/domain/acesso.dart';
import '../repositories/estoque_repository.dart';
import '../services/session_controller.dart';
import 'produtos_loja_page.dart';
import 'produto_fornecedores_page.dart';

class EstoquePage extends StatefulWidget {
  const EstoquePage({super.key});

  @override
  State<EstoquePage> createState() => _EstoquePageState();
}

class _EstoquePageState extends State<EstoquePage> {
  static const Color _roxo = Color(0xFF70569A);
  static const Color _fundo = Color(0xFFF9F6FC);
  static const Color _texto = Color(0xFF2D2140);

  final EstoqueRepository _repository = EstoqueRepository();
  ResumoEstoque _resumo = ResumoEstoque.vazio();
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    try {
      final resumo = await _repository.resumo();
      if (!mounted) return;
      setState(() {
        _resumo = resumo;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
      });
    }
  }

  String _formatarDinheiro(double valor) {
    return 'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  Future<void> abrir(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) {
      setState(() => _carregando = true);
      _carregarDados();
    }
  }

  Widget _buildGroupTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildItem(
    String titulo,
    String subtitulo,
    IconData icone,
    AcaoPermissao permissao,
    VoidCallback acao,
  ) {
    if (!SessionController.instance.usuario!.podeAcao(permissao)) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: Icon(icone, color: Theme.of(context).colorScheme.primary),
        title: Text(titulo),
        subtitle: Text(subtitulo),
        trailing: const Icon(Icons.chevron_right),
        onTap: acao,
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
                  'Valor imobilizado/interno',
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
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundo,
      appBar: AppBar(
        backgroundColor: _fundo,
        title: const Text(
          'Estoque do Salão',
          style: TextStyle(fontWeight: FontWeight.bold, color: _texto),
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: () {
              setState(() => _carregando = true);
              _carregarDados();
            },
            icon: const Icon(Icons.refresh, color: _roxo),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _construirResumo(),

                _buildGroupTitle('OPERAÇÕES'),
                _buildItem(
                  'Produtos de uso interno',
                  'Itens não destinados à venda',
                  Icons.inventory,
                  AcaoPermissao.visualizarEstoque,
                  () => abrir(const ProdutosLojaPage(somenteUsoInterno: true)),
                ),
                _buildItem(
                  'Movimentações',
                  'Entradas, saídas e histórico',
                  Icons.swap_vert,
                  AcaoPermissao.movimentarEstoque,
                  () => abrir(const EstoqueMovimentacoesPage()),
                ),
                _buildItem(
                  'Perdas e avarias',
                  'Registros de dano ou validade',
                  Icons.delete_outline,
                  AcaoPermissao.movimentarEstoque,
                  () => abrir(const EstoqueMovimentacoesPage(perdas: true)),
                ),
                _buildItem(
                  'Estoque baixo',
                  'Reposição necessária',
                  Icons.warning_amber,
                  AcaoPermissao.visualizarEstoque,
                  () => abrir(
                    const ProdutosLojaPage(
                      somenteBaixo: true,
                      somenteUsoInterno: true,
                    ),
                  ),
                ),

                _buildGroupTitle('COMPRAS E IMOBILIZADOS'),
                _buildItem(
                  'Compras e fornecedores',
                  'Gerenciar aquisições',
                  Icons.local_shipping_outlined,
                  AcaoPermissao.cadastrarFornecedor,
                  () => abrir(const ProdutoFornecedoresPage()),
                ),
                _buildItem(
                  'Ativos imobilizados',
                  'Móveis, equipamentos e bens',
                  Icons.chair_alt,
                  AcaoPermissao.visualizarEstoque,
                  () => abrir(const ProdutosLojaPage(somenteAtivos: true)),
                ),

                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Card(
                    child: ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('Consumo por serviço'),
                      subtitle: Text(
                        'A baixa automática por agendamento será ativada na próxima fase.',
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class EstoqueMovimentacoesPage extends StatelessWidget {
  final bool perdas;
  const EstoqueMovimentacoesPage({super.key, this.perdas = false});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(perdas ? 'Perdas e avarias' : 'Movimentações')),
    body: FutureBuilder<List<MovimentacaoEstoqueRegistro>>(
      future: EstoqueRepository().listarMovimentacoes(limite: 500),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!.where((movement) {
          if (!perdas) return true;
          final text = '${movement.tipo} ${movement.motivo}'.toLowerCase();
          return [
            'perda',
            'avaria',
            'dano',
            'validade',
            'desperdício',
          ].any(text.contains);
        }).toList();
        if (rows.isEmpty) {
          return Center(
            child: Text(
              perdas
                  ? 'Nenhuma perda ou avaria registrada.'
                  : 'Nenhuma movimentação registrada.',
            ),
          );
        }
        return ListView.builder(
          itemCount: rows.length,
          itemBuilder: (_, index) {
            final movement = rows[index];
            return ListTile(
              leading: Icon(
                perdas ? Icons.report_problem_outlined : Icons.swap_vert,
              ),
              title: Text('${movement.tipo} • ${movement.quantidade}'),
              subtitle: Text(
                '${movement.motivo}\n${movement.quantidadeAnterior} → ${movement.quantidadePosterior}',
              ),
              isThreeLine: true,
            );
          },
        );
      },
    ),
  );
}
