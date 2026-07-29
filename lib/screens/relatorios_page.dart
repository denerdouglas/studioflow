import 'package:flutter/material.dart';

import '../repositories/relatorios_repository.dart';

const Color kRelatorioPrincipal = Color(0xFF70569A);

const Color kRelatorioFundo = Color(0xFFF9F6FC);

const Color kRelatorioTexto = Color(0xFF2D2140);

class RelatoriosPage extends StatefulWidget {
  const RelatoriosPage({super.key});

  @override
  State<RelatoriosPage> createState() => _RelatoriosPageState();
}

class _RelatoriosPageState extends State<RelatoriosPage> {
  final RelatoriosRepository repository = RelatoriosRepository();

  bool carregando = true;

  RelatorioResumo? resumo;

  double faturamentoHoje = 0;

  double faturamentoMes = 0;

  double lucroMes = 0;

  int clientes = 0;

  int atendimentos = 0;

  int servicos = 0;

  int profissionais = 0;

  @override
  void initState() {
    super.initState();
    carregar();
  }

  Future<void> carregar() async {
    final r = await repository.resumoGeral();

    faturamentoHoje = await repository.faturamentoHoje();

    faturamentoMes = await repository.faturamentoMesAtual();

    lucroMes = await repository.lucroMesAtual();

    clientes = await repository.quantidadeClientes();

    atendimentos = await repository.totalAtendimentosMesAtual();

    servicos = await repository.quantidadeServicos();

    profissionais = await repository.quantidadeProfissionais();

    if (!mounted) {
      return;
    }

    setState(() {
      resumo = r;
      carregando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kRelatorioFundo,
      appBar: AppBar(
        title: const Text('Relatórios'),
        backgroundColor: kRelatorioFundo,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(onPressed: carregar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                _cardPrincipal(),
                const SizedBox(height: 16),
                _gridResumo(),
              ],
            ),
    );
  }

  Widget _cardPrincipal() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF70569A), Color(0xFF9A78C5)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Faturamento do mês',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Text(
            'R\$ ${faturamentoMes.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 30,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Lucro: R\$ ${lucroMes.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _gridResumo() {
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      crossAxisCount: 2,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      childAspectRatio: 1.15,
      children: [
        _ItemResumo(
          titulo: 'Hoje',
          valor: 'R\$ ${faturamentoHoje.toStringAsFixed(2)}',
          icone: Icons.today,
          cor: Colors.green,
        ),
        _ItemResumo(
          titulo: 'Clientes',
          valor: clientes.toString(),
          icone: Icons.people,
          cor: Colors.blue,
        ),
        _ItemResumo(
          titulo: 'Atendimentos',
          valor: atendimentos.toString(),
          icone: Icons.calendar_month,
          cor: Colors.orange,
        ),
        _ItemResumo(
          titulo: 'Serviços',
          valor: servicos.toString(),
          icone: Icons.design_services,
          cor: Colors.purple,
        ),
        _ItemResumo(
          titulo: 'Profissionais',
          valor: profissionais.toString(),
          icone: Icons.badge,
          cor: Colors.indigo,
        ),
        _ItemResumo(
          titulo: 'Lucro',
          valor: 'R\$ ${lucroMes.toStringAsFixed(2)}',
          icone: Icons.trending_up,
          cor: Colors.teal,
        ),
      ],
    );
  }
}

class _ItemResumo extends StatelessWidget {
  final String titulo;
  final String valor;
  final IconData icone;
  final Color cor;

  const _ItemResumo({
    required this.titulo,
    required this.valor,
    required this.icone,
    required this.cor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7DFF2)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: cor.withValues(alpha: 0.15),
            child: Icon(icone, color: cor),
          ),
          const SizedBox(height: 12),
          Text(titulo, style: const TextStyle(color: Color(0xFF766A85))),
          const SizedBox(height: 6),
          Text(
            valor,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: kRelatorioTexto,
            ),
          ),
        ],
      ),
    );
  }
}
