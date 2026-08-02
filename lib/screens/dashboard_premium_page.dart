import 'package:flutter/material.dart';

import '../core/theme/studioflow_theme.dart';
import '../models/domain/acesso.dart';
import '../services/session_controller.dart';
import 'agenda_page.dart';
import 'clientes_page.dart';
import 'home_premium_page.dart';
import 'mais_premium_page.dart';
import 'marketplace_page.dart';
import '../controllers/marketplace_controller.dart';
import '../repositories/marketplace_repository.dart';
import '../repositories/recommendation_engine.dart';
import '../repositories/estoque_repository.dart';


class DashboardPremiumPage extends StatefulWidget {
  final String nomeResponsavel;
  final String nomeNegocio;
  final String tipoNegocio;
  final StudioFlowTheme tema;

  const DashboardPremiumPage({
    super.key,
    required this.nomeResponsavel,
    required this.nomeNegocio,
    required this.tipoNegocio,
    required this.tema,
  });

  @override
  State<DashboardPremiumPage> createState() => _DashboardPremiumPageState();
}

class _DashboardPremiumPageState extends State<DashboardPremiumPage> {
  int _paginaSelecionada = 0;


  late final MarketplaceController _marketplaceController;

  @override
  void initState() {
    super.initState();
    _marketplaceController = MarketplaceController(
      marketplaceRepository: MarketplaceRepository(),
      recommendationEngine: RecommendationEngine(
        estoqueRepository: EstoqueRepository(),
      ),
    );
  }

  @override
  void dispose() {
    _marketplaceController.dispose();
    super.dispose();
  }

  void _mudarPagina(int indice) {
    setState(() {
      _paginaSelecionada = indice;
    });
  }

  @override
  Widget build(BuildContext context) {
    final paginas = [
      HomePremiumPage(
        nomeResponsavel: widget.nomeResponsavel,
        nomeNegocio: widget.nomeNegocio,
        tema: widget.tema,
      ),
      SessionController.instance.usuario!.pode(ModuloPermissao.agenda)
          ? const AgendaPage()
          : const Center(child: Text('Acesso não permitido.')),
      SessionController.instance.usuario!.pode(ModuloPermissao.clientes)
          ? const ClientesPage()
          : const Center(child: Text('Acesso não permitido.')),
      MarketplacePage(controller: _marketplaceController), // const MarketplaceStubPage(),
      // Use MaisSprint2Page until Etapa 3A.2 creates MaisPremiumPage
      MaisPremiumPage(tema: widget.tema),
    ];

    return Scaffold(
      backgroundColor: widget.tema.fundo,
      body: IndexedStack(
        index: _paginaSelecionada,
        children: paginas,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _paginaSelecionada,
        backgroundColor: Colors.white,
        indicatorColor: widget.tema.corPrincipal.withValues(alpha: 0.14),
        onDestinationSelected: _mudarPagina,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Agenda',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Clientes',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Loja',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu),
            selectedIcon: Icon(Icons.menu_open),
            label: 'Mais',
          ),
        ],
      ),
    );
  }
}
