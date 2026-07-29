import 'package:flutter/material.dart';

import '../core/routes/app_routes.dart';

import '../core/theme/studioflow_theme.dart';
import 'agenda_page.dart';
import 'caixa_page.dart';
import 'clientes_page.dart';
import 'comissoes_page.dart';
import 'estoque_page.dart';
import 'financeiro_page.dart';
import 'funcionarios_page.dart';
import 'pacotes_page.dart';
import 'relatorios_page.dart';
import 'servicos_page.dart';

class MaisPage extends StatelessWidget {
  final StudioFlowTheme tema;

  const MaisPage({super.key, required this.tema});

  static const Color _textoEscuro = Color(0xFF2D2140);

  static const Color _textoClaro = Color(0xFF766A85);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: tema.fundo,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: tema.fundo,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Mais recursos',
          style: TextStyle(color: _textoEscuro, fontWeight: FontWeight.bold),
        ),
      ),
      body: GridView.count(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 110),
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 1.05,
        children: [
          _MenuCard(
            titulo: 'Serviços',
            subtitulo: 'Preços e duração',
            icone: Icons.design_services_outlined,
            cor: tema.corPrincipal,
            onTap: () {
              Navigator.push(
                context,
                AppRoutes.material(builder: (_) => const ServicosPage()),
              );
            },
          ),
          _MenuCard(
            titulo: 'Agenda',
            subtitulo: 'Horários e atendimentos',
            icone: Icons.calendar_month_outlined,
            cor: const Color(0xFF3078C5),
            onTap: () {
              Navigator.push(
                context,
                AppRoutes.material(builder: (_) => const AgendaPage()),
              );
            },
          ),
          _MenuCard(
            titulo: 'Clientes',
            subtitulo: 'Cadastro e histórico',
            icone: Icons.people_outline,
            cor: const Color(0xFF15996B),
            onTap: () {
              Navigator.push(
                context,
                AppRoutes.material(builder: (_) => const ClientesPage()),
              );
            },
          ),
          _MenuCard(
            titulo: 'Pacotes',
            subtitulo: 'Vendas e sessões',
            icone: Icons.card_giftcard,
            cor: const Color(0xFF7A4FC2),
            onTap: () {
              Navigator.push(
                context,
                AppRoutes.material(builder: (_) => const PacotesPage()),
              );
            },
          ),
          _MenuCard(
            titulo: 'Caixa',
            subtitulo: 'Entradas e saídas',
            icone: Icons.account_balance_wallet_outlined,
            cor: const Color(0xFFE58A25),
            onTap: () {
              Navigator.push(
                context,
                AppRoutes.material(builder: (_) => const CaixaPage()),
              );
            },
          ),
          _MenuCard(
            titulo: 'Estoque',
            subtitulo: 'Produtos e materiais',
            icone: Icons.inventory_2_outlined,
            cor: const Color(0xFFF06435),
            onTap: () {
              Navigator.push(
                context,
                AppRoutes.material(builder: (_) => const EstoquePage()),
              );
            },
          ),
          _MenuCard(
            titulo: 'Financeiro',
            subtitulo: 'Contas e resultados',
            icone: Icons.payments_outlined,
            cor: const Color(0xFF008F83),
            onTap: () {
              Navigator.push(
                context,
                AppRoutes.material(builder: (_) => const FinanceiroPage()),
              );
            },
          ),
          _MenuCard(
            titulo: 'Funcionários',
            subtitulo: 'Equipe e profissionais',
            icone: Icons.badge_outlined,
            cor: const Color(0xFF4F65B8),
            onTap: () {
              Navigator.push(
                context,
                AppRoutes.material(builder: (_) => const FuncionariosPage()),
              );
            },
          ),
          _MenuCard(
            titulo: 'Comissões',
            subtitulo: 'Valores da equipe',
            icone: Icons.percent,
            cor: const Color(0xFFD93B78),
            onTap: () {
              Navigator.push(
                context,
                AppRoutes.material(builder: (_) => const ComissoesPage()),
              );
            },
          ),
          _MenuCard(
            titulo: 'Relatórios',
            subtitulo: 'Análises do negócio',
            icone: Icons.bar_chart_outlined,
            cor: const Color(0xFF1595B5),
            onTap: () {
              Navigator.push(
                context,
                AppRoutes.material(builder: (_) => const RelatoriosPage()),
              );
            },
          ),
          _MenuCard(
            titulo: 'Fidelidade',
            subtitulo: 'Pontos e recompensas',
            icone: Icons.card_giftcard,
            cor: const Color(0xFFE14D5A),
            onTap: () {
              _mostrarEmBreve(context, 'Fidelidade');
            },
          ),
          _MenuCard(
            titulo: 'StudioFlow IA',
            subtitulo: 'Insights inteligentes',
            icone: Icons.auto_awesome,
            cor: const Color(0xFF6D4ACB),
            onTap: () {
              _mostrarEmBreve(context, 'StudioFlow IA');
            },
          ),
          _MenuCard(
            titulo: 'Configurações',
            subtitulo: 'Preferências do aplicativo',
            icone: Icons.settings_outlined,
            cor: const Color(0xFF66737C),
            onTap: () {
              _mostrarEmBreve(context, 'Configurações');
            },
          ),
        ],
      ),
    );
  }

  void _mostrarEmBreve(BuildContext context, String modulo) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$modulo será conectado em uma próxima etapa.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final IconData icone;
  final Color cor;
  final VoidCallback onTap;

  const _MenuCard({
    required this.titulo,
    required this.subtitulo,
    required this.icone,
    required this.cor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE6DFF0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x10000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icone, color: cor, size: 31),
              ),
              const SizedBox(height: 13),
              Text(
                titulo,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: MaisPage._textoEscuro,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitulo,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  color: MaisPage._textoClaro,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
